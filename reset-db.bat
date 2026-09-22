@echo off
setlocal EnableDelayedExpansion

:: Wipes every DevBoard database and rebuilds the stack from scratch.
::
:: Takes a real backup first: pg_dumpall covers all five Postgres databases AND
:: their roles in one file, mongodump covers the whole activity log, mc mirror
:: covers every object in the MinIO bucket. All three are restored together —
:: restoring Postgres alone brings back attachments_db rows that point at
:: files no longer in MinIO, so the bucket backup is what keeps those links
:: working after a restore.
::
:: The service list lives in SERVICES, once. Rebuild delegates to setup.bat
:: rather than repeating the user/database creation, so this script cannot
:: drift out of date as services are added.

set ROOT=%~dp0
set INFRA_DIR=%ROOT%
set ATTACHMENTS_DIR=%ROOT%..\devboard-attachments
set SERVICES=auth email core work integrations analytics attachments web

echo.
echo ============================================================
echo  DevBoard DB Reset
echo ============================================================
echo.
echo  This DESTROYS all data in:
echo.
echo    Postgres  - auth_db, core_db, work_db, integrations_db, attachments_db
echo    MongoDB   - activity_db (the entire activity log)
echo    Redis     - the event stream, both consumer-group offsets, and devboard-web's login sessions
echo    MinIO     - every uploaded file
echo.
echo  Postgres, MongoDB and the MinIO bucket are backed up first.
echo.

set CONFIRM=
set /p CONFIRM="Type DESTROY to continue, anything else to abort: "
if /i not "%CONFIRM%"=="DESTROY" (
    echo.
    echo  Aborted. Nothing was changed.
    echo.
    exit /b 0
)
echo.

:: ── Read credentials ─────────────────────────────────────────
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^POSTGRES_USER' | ForEach-Object { $_ -replace 'POSTGRES_USER=', '' }"`) do set PG_USER=%%i
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^MONGO_ROOT_USER' | ForEach-Object { $_ -replace 'MONGO_ROOT_USER=', '' }"`) do set MONGO_USER=%%i
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^MONGO_ROOT_PASSWORD' | ForEach-Object { $_ -replace 'MONGO_ROOT_PASSWORD=', '' }"`) do set MONGO_PASS=%%i
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^MINIO_ROOT_USER' | ForEach-Object { $_ -replace 'MINIO_ROOT_USER=', '' }"`) do set MINIO_USER=%%i
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^MINIO_ROOT_PASSWORD' | ForEach-Object { $_ -replace 'MINIO_ROOT_PASSWORD=', '' }"`) do set MINIO_PASS=%%i
for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%ATTACHMENTS_DIR%\.env') | Select-String '^S3_BUCKET' | ForEach-Object { $_ -replace 'S3_BUCKET=', '' }"`) do set S3_BUCKET=%%i

for /f "usebackq tokens=*" %%i in (`powershell -command "Get-Date -Format yyyy-MM-dd_HHmmss"`) do set STAMP=%%i
set BACKUP_DIR=%ROOT%backups\%STAMP%
mkdir "%BACKUP_DIR%" 2>nul

:: ── Back up Postgres (all databases + roles) ─────────────────
echo [1/6] Backing up Postgres ^(all databases and roles^)...
set PG_OK=1
docker exec devboard-db pg_dumpall -U %PG_USER% -f /tmp/devboard_all.sql
if errorlevel 1 (
    set PG_OK=0
) else (
    docker cp devboard-db:/tmp/devboard_all.sql "%BACKUP_DIR%\postgres_all.sql"
    if errorlevel 1 set PG_OK=0
)

if "!PG_OK!"=="0" (
    echo       [WARN] Postgres backup FAILED - is devboard-db running?
) else (
    echo       Saved to %BACKUP_DIR%\postgres_all.sql
)
echo.

:: ── Back up Mongo ────────────────────────────────────────────
echo [2/6] Backing up MongoDB...
set MONGO_OK=1
docker exec devboard-mongo mongodump -u %MONGO_USER% -p %MONGO_PASS% --authenticationDatabase admin --archive=/tmp/devboard_mongo.archive --quiet
if errorlevel 1 (
    set MONGO_OK=0
) else (
    docker cp devboard-mongo:/tmp/devboard_mongo.archive "%BACKUP_DIR%\mongo.archive"
    if errorlevel 1 set MONGO_OK=0
)

if "!MONGO_OK!"=="0" (
    echo       [WARN] Mongo backup FAILED - is devboard-mongo running, and does
    echo              the image include mongodump?
) else (
    echo       Saved to %BACKUP_DIR%\mongo.archive
)
echo.

:: ── Back up the MinIO bucket ───────────────────────────────────
:: mc mirror is used with a throwaway alias rather than the pre-configured
:: "local" one, which has no credentials set. Mirrors into the container's
:: own /tmp first, then docker cp pulls the folder out — same shape as the
:: Postgres and Mongo dumps above.
echo [3/6] Backing up MinIO bucket...
set MINIO_OK=1
docker exec devboard-minio mc alias set resetbackup http://localhost:9000 %MINIO_USER% %MINIO_PASS% >nul 2>&1
if errorlevel 1 set MINIO_OK=0

if "!MINIO_OK!"=="1" (
    docker exec devboard-minio rm -rf /tmp/devboard_bucket_backup >nul 2>&1
    docker exec devboard-minio mc mirror --quiet resetbackup/%S3_BUCKET% /tmp/devboard_bucket_backup
    if errorlevel 1 set MINIO_OK=0
)

if "!MINIO_OK!"=="1" (
    docker cp devboard-minio:/tmp/devboard_bucket_backup "%BACKUP_DIR%\minio_bucket"
    if errorlevel 1 set MINIO_OK=0
)

docker exec devboard-minio rm -rf /tmp/devboard_bucket_backup >nul 2>&1
docker exec devboard-minio mc alias remove resetbackup >nul 2>&1

if "!MINIO_OK!"=="0" (
    echo       [WARN] MinIO backup FAILED - is devboard-minio running?
) else (
    echo       Saved to %BACKUP_DIR%\minio_bucket
)
echo.

:: ── Second gate if any backup failed ──────────────────────────
if "!PG_OK!"=="0" set BACKUP_FAILED=1
if "!MONGO_OK!"=="0" set BACKUP_FAILED=1
if "!MINIO_OK!"=="0" set BACKUP_FAILED=1

if defined BACKUP_FAILED (
    echo  ------------------------------------------------------------
    echo   At least one backup did not complete. Continuing will destroy
    echo   that data with no way to get it back.
    echo  ------------------------------------------------------------
    echo.
    set CONFIRM2=
    set /p CONFIRM2="Type DESTROY again to proceed anyway: "
    if /i not "!CONFIRM2!"=="DESTROY" (
        echo.
        echo  Aborted. Nothing was destroyed. Backups kept in %BACKUP_DIR%
        echo.
        exit /b 0
    )
    echo.
)

:: ── Tear down ────────────────────────────────────────────────
echo [4/6] Stopping services...
for %%s in (%SERVICES%) do (
    docker compose -f "%ROOT%..\devboard-%%s\docker-compose.yml" down >nul 2>&1
    echo       devboard-%%s stopped.
)
echo.

echo [5/6] Removing infrastructure volumes...
docker compose -f "%INFRA_DIR%docker-compose.yml" down -v
if errorlevel 1 (
    echo [ERROR] Failed to tear down infrastructure. Backups are in %BACKUP_DIR%
    exit /b 1
)
echo       Postgres, Mongo, Redis and MinIO volumes removed.
echo.

:: ── Rebuild ──────────────────────────────────────────────────
:: setup.bat owns the service list, user/database creation and migrations.
:: Calling it is what stops this script from going stale.
echo [6/6] Rebuilding the stack via setup.bat...
echo.
call "%INFRA_DIR%setup.bat"

:: setup.bat now exits 1 when any migration failed. Don't claim success over it.
if errorlevel 1 (
    echo.
    echo ############################################################
    echo  [ERROR] Reset tore down and rebuilt the stack, but setup.bat
    echo          reported failures - see above.
    echo.
    echo  Your pre-reset backup is intact at:
    echo    %BACKUP_DIR%
    echo ############################################################
    echo.
    exit /b 1
)

echo.
echo ============================================================
echo  Reset complete. Databases are empty and migrated.
echo.
echo  Backup: %BACKUP_DIR%
echo.
echo  To restore Postgres into the fresh stack:
echo    docker cp "%BACKUP_DIR%\postgres_all.sql" devboard-db:/tmp/restore.sql
echo    docker exec devboard-db psql -U %PG_USER% -f /tmp/restore.sql
echo.
echo  To restore MongoDB:
echo    docker cp "%BACKUP_DIR%\mongo.archive" devboard-mongo:/tmp/restore.archive
echo    docker exec devboard-mongo mongorestore --archive=/tmp/restore.archive ^
echo      -u %MONGO_USER% -p ^<password^> --authenticationDatabase admin --drop
echo.
echo  To restore the MinIO bucket:
echo    docker exec devboard-minio mc alias set restore http://localhost:9000 ^<user^> ^<password^>
echo    docker cp "%BACKUP_DIR%\minio_bucket" devboard-minio:/tmp/restore_bucket
echo    docker exec devboard-minio mc mirror /tmp/restore_bucket restore/%S3_BUCKET%
echo.
echo  Restore over a migrated database, not alongside it - pg_dumpall recreates
echo  roles and tables, so expect "already exists" errors on the role lines.
echo  Restore Postgres AND the MinIO bucket together - attachments_db rows
echo  point at files by key, so restoring only one side leaves broken links.
echo ============================================================
echo.

endlocal
