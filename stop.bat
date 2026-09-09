@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set INFRA_DIR=%ROOT%
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set INTEGRATIONS_DIR=%ROOT%..\devboard-integrations
set ANALYTICS_DIR=%ROOT%..\devboard-analytics
set ATTACHMENTS_DIR=%ROOT%..\devboard-attachments
set DUMP_FILE=%ROOT%backups\devboard_all.sql

echo.
echo ============================================================
echo  DevBoard Stop
echo ============================================================
echo.

:: ── Dump databases before stopping ───────────────────────────
:: pg_dumpall, not pg_dump -d auth_db: the old version claimed to have taken a
:: backup while covering one of five databases. `down` below keeps the volumes,
:: so this is belt-and-braces either way — but the message it prints is now true.
echo [1/2] Backing up Postgres...

mkdir "%ROOT%backups" 2>nul

for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^POSTGRES_USER' | ForEach-Object { $_ -replace 'POSTGRES_USER=', '' }"`) do set PG_USER=%%i

docker exec devboard-db pg_dumpall -U %PG_USER% -f /tmp/devboard_all.sql

if errorlevel 1 (
    echo [WARN] Backup failed — container may not be running.
) else (
    docker cp devboard-db:/tmp/devboard_all.sql "%DUMP_FILE%"
    echo       All databases and roles saved to %DUMP_FILE%
)
echo.

:: ── Stop all containers ───────────────────────────────────────
echo [2/2] Stopping all containers...
docker compose -f "%ATTACHMENTS_DIR%\docker-compose.yml" down
docker compose -f "%ANALYTICS_DIR%\docker-compose.yml" down
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" down
docker compose -f "%EMAIL_DIR%\docker-compose.yml" down
docker compose -f "%WORK_DIR%\docker-compose.yml" down
docker compose -f "%CORE_DIR%\docker-compose.yml" down
docker compose -f "%AUTH_DIR%\docker-compose.yml" down
docker compose -f "%INFRA_DIR%docker-compose.yml" down
echo       Done.
echo.

echo ============================================================
echo  All containers stopped. Data is safe in the volume.
echo  Backup saved to: %DUMP_FILE%
echo ============================================================
echo.

endlocal
