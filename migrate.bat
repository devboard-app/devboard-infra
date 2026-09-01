@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set AUTH_DIR=%ROOT%..\devboard-auth
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set INTEGRATIONS_DIR=%ROOT%..\devboard-integrations
set ATTACHMENTS_DIR=%ROOT%..\devboard-attachments

set SUMMARY_FILE=%TEMP%\devboard_migrate_summary.txt
if exist "%SUMMARY_FILE%" del "%SUMMARY_FILE%"

echo.
echo ============================================================
echo  DevBoard Migrations
echo ============================================================
echo.
echo  0 - All services
echo  1 - devboard-auth          (alembic)
echo  2 - devboard-core          (django)
echo  3 - devboard-work          (django)
echo  4 - devboard-integrations  (alembic)
echo  5 - devboard-attachments   (alembic)
echo.
set /p CHOICE="Select service to migrate: "

if "%CHOICE%"=="0" goto ALL
if "%CHOICE%"=="1" goto AUTH
if "%CHOICE%"=="2" goto CORE
if "%CHOICE%"=="3" goto WORK
if "%CHOICE%"=="4" goto INTEGRATIONS
if "%CHOICE%"=="5" goto ATTACHMENTS

echo Invalid choice.
exit /b 1

:ALL
call :RUN_AUTH
call :RUN_CORE
call :RUN_WORK
call :RUN_INTEGRATIONS
call :RUN_ATTACHMENTS
goto DONE

:AUTH
call :RUN_AUTH
goto DONE

:CORE
call :RUN_CORE
goto DONE

:WORK
call :RUN_WORK
goto DONE

:INTEGRATIONS
call :RUN_INTEGRATIONS
goto DONE

:ATTACHMENTS
call :RUN_ATTACHMENTS
goto DONE

:RUN_AUTH
echo Migrating devboard-auth (alembic)...
docker compose -f "%AUTH_DIR%\docker-compose.yml" exec devboard-auth alembic upgrade head
if errorlevel 1 (
    echo   [FAILED] devboard-auth          ->  check output above >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-auth          ->  migrated >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_CORE
echo Migrating devboard-core (django)...
docker compose -f "%CORE_DIR%\docker-compose.yml" exec devboard-core python manage.py migrate
if errorlevel 1 (
    echo   [FAILED] devboard-core          ->  check output above >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-core          ->  migrated >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_WORK
echo Migrating devboard-work (django)...
docker compose -f "%WORK_DIR%\docker-compose.yml" exec devboard-work python manage.py migrate
if errorlevel 1 (
    echo   [FAILED] devboard-work          ->  check output above >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-work          ->  migrated >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_INTEGRATIONS
echo Migrating devboard-integrations (alembic)...
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" exec devboard-integrations alembic upgrade head
if errorlevel 1 (
    echo   [FAILED] devboard-integrations  ->  check output above >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-integrations  ->  migrated >> "%SUMMARY_FILE%"
)
exit /b 0

:RUN_ATTACHMENTS
echo Migrating devboard-attachments (alembic)...
docker compose -f "%ATTACHMENTS_DIR%\docker-compose.yml" exec devboard-attachments alembic upgrade head
if errorlevel 1 (
    echo   [FAILED] devboard-attachments   ->  check output above >> "%SUMMARY_FILE%"
) else (
    echo   [OK]     devboard-attachments   ->  migrated >> "%SUMMARY_FILE%"
)
exit /b 0

:DONE
echo.
echo ============================================================
echo  Migration Summary
echo ============================================================
echo.
type "%SUMMARY_FILE%"
del "%SUMMARY_FILE%"
echo.
echo ============================================================
echo.

endlocal
