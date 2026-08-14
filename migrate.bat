@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set AUTH_DIR=%ROOT%..\devboard-auth
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work

echo.
echo ============================================================
echo  DevBoard Migrations
echo ============================================================
echo.

echo [1/3] Running alembic migrations inside devboard-auth...
docker compose -f "%AUTH_DIR%\docker-compose.yml" exec devboard-auth alembic upgrade head

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-auth migration failed. Check the output above.
    exit /b 1
)

echo.
echo [2/3] Running Django migrations inside devboard-core...
docker compose -f "%CORE_DIR%\docker-compose.yml" exec devboard-core python manage.py migrate

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-core migration failed. Check the output above.
    exit /b 1
)

echo.
echo [3/3] Running Django migrations inside devboard-work...
docker compose -f "%WORK_DIR%\docker-compose.yml" exec devboard-work python manage.py migrate

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-work migration failed. Check the output above.
    exit /b 1
)

echo.
echo Done.
echo.

endlocal
