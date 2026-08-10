@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core

echo.
echo ============================================================
echo  DevBoard Redeploy
echo ============================================================
echo.

echo Rebuilding and restarting app containers...

docker compose -f "%AUTH_DIR%\docker-compose.yml" up --build -d devboard-auth
if errorlevel 1 (
    echo [ERROR] devboard-auth redeploy failed.
    exit /b 1
)

docker compose -f "%CORE_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo [ERROR] devboard-core redeploy failed.
    exit /b 1
)

docker compose -f "%EMAIL_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo [ERROR] devboard-email redeploy failed.
    exit /b 1
)

echo.
echo ============================================================
echo  Done.
echo.
echo  devboard-auth  : http://localhost:8001
echo  devboard-email : http://localhost:8002
echo  devboard-core  : http://localhost:8003
echo ============================================================
echo.

endlocal
