@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set INFRA_DIR=%ROOT%
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set DUMP_FILE=%ROOT%auth_db_backup.dump

echo.
echo ============================================================
echo  DevBoard Stop
echo ============================================================
echo.

:: ── Dump database before stopping ────────────────────────────
echo [1/2] Backing up database...
docker exec devboard-db pg_dump -U auth_user -F c -d auth_db -f /auth_db_backup.dump

if errorlevel 1 (
    echo [WARN] Database backup failed — container may not be running.
) else (
    docker cp devboard-db:/auth_db_backup.dump "%DUMP_FILE%"
    echo       Backup saved to %DUMP_FILE%
)
echo.

:: ── Stop all containers ───────────────────────────────────────
echo [2/2] Stopping all containers...
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
