@echo off
setlocal EnableDelayedExpansion

set ROOT=%~dp0
set INFRA_DIR=%ROOT%
set AUTH_DIR=%ROOT%..\devboard-auth
set EMAIL_DIR=%ROOT%..\devboard-email
set CORE_DIR=%ROOT%..\devboard-core
set WORK_DIR=%ROOT%..\devboard-work
set INTEGRATIONS_DIR=%ROOT%..\devboard-integrations

echo.
echo ============================================================
echo  DevBoard Docker Setup
echo ============================================================
echo.

:: ── .env checks ─────────────────────────────────────────────
if not exist "%ROOT%.env" (
    echo [WARN] devboard-infra\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%ROOT%.env.example" "%ROOT%.env" >nul
)

if not exist "%AUTH_DIR%\.env" (
    echo [WARN] devboard-auth\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%AUTH_DIR%\.env.example" "%AUTH_DIR%\.env" >nul
)

if not exist "%EMAIL_DIR%\.env" (
    echo [WARN] devboard-email\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%EMAIL_DIR%\.env.example" "%EMAIL_DIR%\.env" >nul
)

if not exist "%CORE_DIR%\.env" (
    echo [WARN] devboard-core\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%CORE_DIR%\.env.example" "%CORE_DIR%\.env" >nul
)

if not exist "%WORK_DIR%\.env" (
    echo [WARN] devboard-work\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%WORK_DIR%\.env.example" "%WORK_DIR%\.env" >nul
)

if not exist "%INTEGRATIONS_DIR%\.env" (
    echo [WARN] devboard-integrations\.env not found.
    echo        Copying from .env.example — fill in the real values before running.
    copy "%INTEGRATIONS_DIR%\.env.example" "%INTEGRATIONS_DIR%\.env" >nul
)

:: ── Start DB ─────────────────────────────────────────────────
echo [1/6] Starting database...
echo       (First run may take a moment)
echo.

docker compose -f "%INFRA_DIR%docker-compose.yml" up -d

if errorlevel 1 (
    echo.
    echo [ERROR] Database failed to start. Check the output above.
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

:: ── Create service users and databases ───────────────────────
echo [2/6] Setting up service users and databases...

for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INFRA_DIR%.env') | Select-String '^POSTGRES_USER' | ForEach-Object { $_ -replace 'POSTGRES_USER=', '' }"`) do set PG_USER=%%i

:: auth_user + auth_db
docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_roles WHERE rolname='auth_user'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%AUTH_DIR%\.env') | Select-String '^AUTH_DB_PASSWORD' | ForEach-Object { $_ -replace 'AUTH_DB_PASSWORD=', '' }"`) do set AUTH_PASS=%%i
    docker exec devboard-db psql -U %PG_USER% -c "CREATE USER auth_user WITH PASSWORD '%AUTH_PASS%';"
    echo       auth_user created.
) else (
    echo       auth_user already exists, skipping.
)

docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_database WHERE datname='auth_db'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE auth_db OWNER auth_user;"
    docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE auth_db TO auth_user;"
    echo       auth_db created.
) else (
    echo       auth_db already exists, skipping.
)

:: core_user + core_db
docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_roles WHERE rolname='core_user'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%CORE_DIR%\.env') | Select-String '^DB_PASSWORD' | ForEach-Object { $_ -replace 'DB_PASSWORD=', '' }"`) do set CORE_PASS=%%i
    docker exec devboard-db psql -U %PG_USER% -c "CREATE USER core_user WITH PASSWORD '%CORE_PASS%';"
    echo       core_user created.
) else (
    echo       core_user already exists, skipping.
)

docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_database WHERE datname='core_db'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE core_db OWNER core_user;"
    docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE core_db TO core_user;"
    echo       core_db created.
) else (
    echo       core_db already exists, skipping.
)

:: work_user + work_db
docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_roles WHERE rolname='work_user'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%WORK_DIR%\.env') | Select-String '^DB_PASSWORD' | ForEach-Object { $_ -replace 'DB_PASSWORD=', '' }"`) do set WORK_PASS=%%i
    docker exec devboard-db psql -U %PG_USER% -c "CREATE USER work_user WITH PASSWORD '%WORK_PASS%';"
    echo       work_user created.
) else (
    echo       work_user already exists, skipping.
)

docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_database WHERE datname='work_db'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE work_db OWNER work_user;"
    docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE work_db TO work_user;"
    echo       work_db created.
) else (
    echo       work_db already exists, skipping.
)

:: integrations_user + integrations_db
docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_roles WHERE rolname='integrations_user'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    for /f "usebackq tokens=*" %%i in (`powershell -command "(Get-Content '%INTEGRATIONS_DIR%\.env') | Select-String '^DB_PASSWORD' | ForEach-Object { $_ -replace 'DB_PASSWORD=', '' }"`) do set INTEGRATIONS_PASS=%%i
    docker exec devboard-db psql -U %PG_USER% -c "CREATE USER integrations_user WITH PASSWORD '%INTEGRATIONS_PASS%';"
    echo       integrations_user created.
) else (
    echo       integrations_user already exists, skipping.
)

docker exec devboard-db psql -U %PG_USER% -tc "SELECT 1 FROM pg_database WHERE datname='integrations_db'" | findstr "1" >nul 2>&1
if errorlevel 1 (
    docker exec devboard-db psql -U %PG_USER% -c "CREATE DATABASE integrations_db OWNER integrations_user;"
    docker exec devboard-db psql -U %PG_USER% -c "GRANT ALL PRIVILEGES ON DATABASE integrations_db TO integrations_user;"
    echo       integrations_db created.
) else (
    echo       integrations_db already exists, skipping.
)
echo.

:: ── Build and start auth ──────────────────────────────────────
echo [3/7] Building and starting devboard-auth...
docker compose -f "%AUTH_DIR%\docker-compose.yml" up --build -d

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-auth compose failed. Check the output above.
    exit /b 1
)

echo       Running alembic migrations...
docker compose -f "%AUTH_DIR%\docker-compose.yml" exec devboard-auth alembic upgrade head

if errorlevel 1 (
    echo [WARN] Migrations failed or alembic not available in container.
)
echo.

:: ── Build and start core ──────────────────────────────────────
echo [4/7] Building and starting devboard-core...
docker compose -f "%CORE_DIR%\docker-compose.yml" up --build -d

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-core compose failed. Check the output above.
    exit /b 1
)

echo       Running Django migrations...
docker compose -f "%CORE_DIR%\docker-compose.yml" exec devboard-core python manage.py migrate

if errorlevel 1 (
    echo [WARN] Django migrations failed.
)
echo.

:: ── Build and start email ─────────────────────────────────────
echo [5/7] Building and starting devboard-work...
docker compose -f "%WORK_DIR%\docker-compose.yml" up --build -d

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-work compose failed. Check the output above.
    exit /b 1
)

echo       Running Django migrations...
docker compose -f "%WORK_DIR%\docker-compose.yml" exec devboard-work python manage.py migrate

if errorlevel 1 (
    echo [WARN] Django migrations failed.
)
echo.

echo [6/7] Building and starting devboard-email...
docker compose -f "%EMAIL_DIR%\docker-compose.yml" up --build -d

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-email compose failed. Check the output above.
    exit /b 1
)
echo.

:: ── Build and start integrations ──────────────────────────────
echo [7/7] Building and starting devboard-integrations...
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" up --build -d

if errorlevel 1 (
    echo.
    echo [ERROR] devboard-integrations compose failed. Check the output above.
    exit /b 1
)

echo       Running alembic migrations...
docker compose -f "%INTEGRATIONS_DIR%\docker-compose.yml" exec devboard-integrations alembic upgrade head

if errorlevel 1 (
    echo [WARN] Migrations failed or alembic not available in container.
)

echo.
echo ============================================================
echo  All services are running.
echo.
echo  devboard-auth         : http://localhost:8001
echo  devboard-email        : http://localhost:8002
echo  devboard-core         : http://localhost:8003
echo  devboard-work         : http://localhost:8004
echo  devboard-integrations : http://localhost:8005
echo  PostgreSQL            : localhost:5432
echo  Redis                 : localhost:6379
echo.
echo  To stop everything: stop.bat
echo ============================================================
echo.

endlocal
