@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set AUTH_DIR=%ROOT%..\devboard-auth
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set INTEGRATIONS_DIR=%ROOT%..\devboard-integrations

echo.
echo ============================================================
echo  DevBoard Migrations
echo ============================================================
echo.

echo [1/4] Running alembic migrations inside devboard-auth...
docker compose -f "%AUTH_DIR%\docker-compose.yml" exec devboard-auth alembic upgrade head

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-auth migration failed. Check the output above.
    exit /b 1
)

echo.
echo [2/4] Running Django migrations inside devboard-core...
docker compose -f "%CORE_DIR%\docker-compose.yml" exec devboard-core python manage.py migrate

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-core migration failed. Check the output above.
    exit /b 1
)

echo.
echo [3/4] Running Django migrations inside devboard-work...
docker compose -f "%WORK_DIR%\docker-compose.yml" exec devboard-work python manage.py migrate

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-work migration failed. Check the output above.
    exit /b 1
)

echo.
echo [4/4] Running alembic migrations inside devboard-integrations...
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" exec devboard-integrations alembic upgrade head

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-integrations migration failed. Check the output above.
    exit /b 1
)

echo.
echo Done.
echo.

endlocal
