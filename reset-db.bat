@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set INFRA_DIR=%ROOT%
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core
set DUMP_FILE=%ROOT%auth_db_backup.dump

echo.
echo ============================================================
echo  DevBoard DB Reset
echo ============================================================
echo.

:: ── Dump existing data from running container ────────────────
echo [1/5] Dumping existing database...
docker exec devboard-db pg_dump -U auth_user -F c -d auth_db -f /auth_db_backup.dump

if errorlevel 1 (
    echo [WARN] Could not dump from container. Trying local PostgreSQL...
    pg_dump -U postgres -d auth_db -F c -f "%DUMP_FILE%"
    if errorlevel 1 (
        echo [ERROR] Dump failed. Make sure the database is accessible.
        exit /b 1
    )
    set DUMP_SOURCE=local
) else (
    docker cp devboard-db:/auth_db_backup.dump "%DUMP_FILE%"
    set DUMP_SOURCE=container
)
echo       Done.
echo.

:: ── Tear down all containers and wipe volume ─────────────────
echo [2/5] Stopping containers and wiping DB volume...
docker compose -f "%EMAIL_DIR%\docker-compose.yml" down
docker compose -f "%CORE_DIR%\docker-compose.yml" down
docker compose -f "%AUTH_DIR%\docker-compose.yml" down
docker compose -f "%INFRA_DIR%docker-compose.yml" down -v
if errorlevel 1 (
    echo [ERROR] Failed to bring down containers.
    exit /b 1
)
echo       Done.
echo.

:: ── Start fresh DB container ─────────────────────────────────
echo [3/5] Starting fresh DB container...
docker compose -f "%INFRA_DIR%docker-compose.yml" up -d
if errorlevel 1 (
    echo [ERROR] Failed to start DB container.
    exit /b 1
)

echo       Waiting for DB to be healthy...
:wait_loop
docker inspect --format="{{.State.Health.Status}}" devboard-db | findstr "healthy" >nul 2>&1
if errorlevel 1 (
    timeout /t 2 >nul
    goto wait_loop
)
echo       Done.
echo.

:: ── Restore dump ─────────────────────────────────────────────
echo [4/5] Restoring data...
docker cp "%DUMP_FILE%" devboard-db:/auth_db_backup.dump
docker exec devboard-db pg_restore -U auth_user -d auth_db /auth_db_backup.dump
echo       Done (ownership warnings are normal).
echo.

:: ── Recreate service users and databases ─────────────────────
echo       Recreating auth_user, core_user and their databases...

for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^POSTGRES_USER' | ForEach-Object { $_ -replace 'POSTGRES_USER=', '' }"`) do set PG_USER=%%i

for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%AUTH_DIR%\.env') | Select-String '^AUTH_DB_PASSWORD' | ForEach-Object { $_ -replace 'AUTH_DB_PASSWORD=', '' }"`) do set AUTH_PASS=%%i
docker exec devboard-db psql -U %PG_USER% -c "CREATE USER auth_user WITH PASSWORD '%AUTH_PASS%';" >nul
docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE auth_db OWNER auth_user;" >nul
docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE auth_db TO auth_user;" >nul

for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%CORE_DIR%\.env') | Select-String '^DB_PASSWORD' | ForEach-Object { $_ -replace 'DB_PASSWORD=', '' }"`) do set CORE_PASS=%%i
docker exec devboard-db psql -U %PG_USER% -c "CREATE USER core_user WITH PASSWORD '%CORE_PASS%';" >nul
docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE core_db OWNER core_user;" >nul
docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE core_db TO core_user;" >nul

echo       Done.
echo.

:: ── Start remaining services ─────────────────────────────────
echo [5/5] Starting all services...
docker compose -f "%AUTH_DIR%\docker-compose.yml" up --build -d
docker compose -f "%CORE_DIR%\docker-compose.yml" up --build -d
docker compose -f "%EMAIL_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo [ERROR] Failed to start services.
    exit /b 1
)
echo       Done.
echo.

echo ============================================================
echo  DB reset complete.
echo.
echo  devboard-auth   ->  http://localhost:8001
echo  devboard-email  ->  http://localhost:8002
echo  devboard-core   ->  http://localhost:8003
echo  PostgreSQL      ->  localhost:5432
echo ============================================================
echo.

endlocal
