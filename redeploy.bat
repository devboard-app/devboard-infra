@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set INTEGRATIONS_DIR=%ROOT%..\devboard-integrations

set SUMMARY_FILE=%TEMP%\devboard_redeploy_summary.txt
if exist "%SUMMARY_FILE%" del "%SUMMARY_FILE%"

echo.
echo ============================================================
echo  DevBoard Redeploy
echo ============================================================
echo.
echo  0 - All services
echo  1 - devboard-core
echo  2 - devboard-auth
echo  3 - devboard-email
echo  4 - devboard-work
echo  5 - devboard-integrations
echo.
set /p CHOICE="Select service to redeploy: "

if "%CHOICE%"=="0" goto ALL
if "%CHOICE%"=="1" goto CORE
if "%CHOICE%"=="2" goto AUTH
if "%CHOICE%"=="3" goto EMAIL
if "%CHOICE%"=="4" goto WORK
if "%CHOICE%"=="5" goto INTEGRATIONS

echo Invalid choice.
exit /b 1

:ALL
call :RUN_AUTH
call :RUN_CORE
call :RUN_EMAIL
call :RUN_WORK
call :RUN_INTEGRATIONS
goto DONE

:AUTH
call :RUN_AUTH
goto DONE

:CORE
call :RUN_CORE
goto DONE

:EMAIL
call :RUN_EMAIL
goto DONE

:WORK
call :RUN_WORK
goto DONE

:INTEGRATIONS
call :RUN_INTEGRATIONS
goto DONE

:RUN_AUTH
echo Redeploying devboard-auth...
docker compose -f "%AUTH_DIR%\docker-compose.yml" up --build -d devboard-auth
if errorlevel 1 (
    echo   [FAILED] devboard-auth         ->  check docker logs >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-auth         ->  http://localhost:8001 >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_CORE
echo Redeploying devboard-core...
docker compose -f "%CORE_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo   [FAILED] devboard-core         ->  check docker logs >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-core         ->  http://localhost:8003 >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_EMAIL
echo Redeploying devboard-email...
docker compose -f "%EMAIL_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo   [FAILED] devboard-email        ->  check docker logs >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-email        ->  http://localhost:8002 >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_WORK
echo Redeploying devboard-work...
docker compose -f "%WORK_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo   [FAILED] devboard-work         ->  check docker logs >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-work         ->  http://localhost:8004 >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_INTEGRATIONS
echo Redeploying devboard-integrations...
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" up --build -d
if errorlevel 1 (
    echo   [FAILED] devboard-integrations ->  check docker logs >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-integrations ->  http://localhost:8005 >> "%SUMMARY_FILE%"
)
exit /b 0

:DONE
echo.
echo ============================================================
echo  Redeploy Summary
echo ============================================================
echo.
type "%SUMMARY_FILE%"
del "%SUMMARY_FILE%"
echo.
echo ============================================================
echo.

endlocal
