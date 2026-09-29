<#
  DevBoard first-time setup on a new machine. Run it through bootstrap.bat.

  1. Checks git and Docker are installed.
  2. Clones every repo next to devboard-infra, each at the branch in $Repos.
  3. Creates each missing .env from its .env.example.
  4. Fills in every secret that is still a placeholder, so the values that
     must match across repos (DB passwords, JWT_SECRET, INTERNAL_API_KEY)
     do match. A value that is already real is never overwritten, so this
     is safe to re-run on a machine that is already set up.
  5. Asks for the settings only you have (SMTP login, Gemini key, GitHub
     webhook secret) and writes them into the right .env. Enter skips one.
  6. Starts the whole stack with stack.yml (migrations included).

  Keep this file ASCII-only: Windows PowerShell 5.1 reads a BOM-less file as
  ANSI, so any non-ASCII character would be mangled.
#>
param(
    # Skip step 6 (clone and configure only).
    [switch]$NoStart,
    # Skip step 5 (don't ask for anything; leave those values for later).
    [switch]$NoPrompt
)

$InfraDir = $PSScriptRoot
$Root = Split-Path $InfraDir -Parent
$GitBase = 'https://github.com/devboard-app'

# The branch each repo is cloned at. Change it here when a branch is merged.
$Repos = [ordered]@{
    'devboard-auth'         = 'dev'
    'devboard-email'        = 'dev'
    'devboard-core'         = 'dev'
    'devboard-work'         = 'dev'
    'devboard-integrations' = 'dev'
    'devboard-analytics'    = 'feat/chat'
    'devboard-attachments'  = 'dev'
    'devboard-web2'         = 'dev'
    'devboard-docs'         = 'dev'
}

# One Postgres/Mongo password per service. The devboard-infra/.env key is the
# source of truth; Keys and UrlKeys are where the same password appears in the
# service's own .env (UrlKeys hold it inside a connection string).
$DbPasswords = @(
    @{ InfraKey = 'AUTH_DB_PASSWORD'; Service = 'devboard-auth'; User = 'auth_user'
       Keys = @('AUTH_DB_PASSWORD'); UrlKeys = @('DATABASE_URL', 'DATABASE_URL_SYNC') }
    @{ InfraKey = 'CORE_DB_PASSWORD'; Service = 'devboard-core'; User = 'core_user'
       Keys = @('DB_PASSWORD'); UrlKeys = @() }
    @{ InfraKey = 'WORK_DB_PASSWORD'; Service = 'devboard-work'; User = 'work_user'
       Keys = @('DB_PASSWORD'); UrlKeys = @() }
    @{ InfraKey = 'INTEGRATIONS_DB_PASSWORD'; Service = 'devboard-integrations'; User = 'integrations_user'
       Keys = @('DB_PASSWORD'); UrlKeys = @() }
    @{ InfraKey = 'ATTACHMENTS_DB_PASSWORD'; Service = 'devboard-attachments'; User = 'attachments_user'
       Keys = @('ATTACHMENTS_DB_PASSWORD'); UrlKeys = @('DATABASE_URL', 'DATABASE_URL_SYNC') }
    @{ InfraKey = 'ANALYTICS_DB_PASSWORD'; Service = 'devboard-analytics'; User = 'analytics_user'
       Keys = @(); UrlKeys = @('MONGO_URI') }
)

# Shared by every service that has the key.
$SharedSecrets = @('JWT_SECRET', 'INTERNAL_API_KEY')

# Keys where an empty value is a real, valid setting.
$EmptyAllowed = @('TRUSTED_PROXY_IPS')

$FrontendUrl = 'http://localhost:8443'

# Settings no one can generate for you, asked for in step 5. Asked only while
# the value is still a placeholder. Skipping a group's first field skips the
# whole group.
$AccountSettings = @(
    @{ Service = 'devboard-email'; Title = 'Email (SMTP) - sends verification and password-reset emails'
       Fields = @(
           @{ Key = 'SMTP_HOST'; Label = 'SMTP host, e.g. smtp.gmail.com' }
           # The email service always uses STARTTLS, which is port 587.
           @{ Key = 'SMTP_PORT'; Label = 'SMTP port'; Default = '587'; Pattern = '^\d+$' }
           @{ Key = 'SMTP_USER'; Label = 'SMTP username' }
           @{ Key = 'SMTP_PASSWORD'; Label = 'SMTP password'; Secret = $true }
           @{ Key = 'MAIL_FROM'; Label = 'From address, e.g. DevBoard <no-reply@example.com>' }
       ) }
    @{ Service = 'devboard-analytics'; Title = 'Gemini - powers the analytics chatbot'
       Fields = @( @{ Key = 'GEMINI_API_KEY'; Label = 'Gemini API key'; Secret = $true } ) }
    @{ Service = 'devboard-integrations'; Title = 'GitHub webhook - must equal the secret set on your GitHub App webhook'
       Fields = @( @{ Key = 'GITHUB_WEBHOOK_SECRET'; Label = 'Webhook secret'; Secret = $true } ) }
)

# -- helpers -----------------------------------------------------------------

function Write-Step([int]$n, [string]$text) {
    Write-Host ''
    Write-Host "[$n/6] $text" -ForegroundColor Cyan
}

function Write-Warn([string]$text) {
    Write-Host "  WARN  $text" -ForegroundColor Yellow
}

function New-Secret([int]$bytes = 32) {
    $buf = New-Object byte[] $bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($buf)
    $rng.Dispose()
    # Hex only, so a generated password never needs escaping in a URL.
    ($buf | ForEach-Object { $_.ToString('x2') }) -join ''
}

# The .env.example files use "...", ".. , ..", "your_*" and "your-*" as
# placeholders. A missing key ($null) counts as one too.
function Test-Placeholder($value) {
    if ($null -eq $value) { return $true }
    $v = $value.Trim()
    return ($v -eq '' -or $v -match '^[.\s,]+$' -or $v -match '(?i)your[_-]' -or $v -eq 'frontend_url')
}

function Read-EnvFile([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    $nl = "`n"
    if ($text.Contains("`r`n")) { $nl = "`r`n" }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($text -split "`r?`n")) { $lines.Add($line) }
    # A trailing newline leaves one empty element; drop it, Save adds it back.
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    return @{ Path = $path; NL = $nl; Lines = $lines; Changed = (New-Object 'System.Collections.Generic.List[string]') }
}

function Find-EnvLine($envFile, [string]$key) {
    $pattern = '^\s*' + [regex]::Escape($key) + '\s*='
    for ($i = 0; $i -lt $envFile.Lines.Count; $i++) {
        if ($envFile.Lines[$i] -match $pattern) { return $i }
    }
    return -1
}

function Get-EnvValue($envFile, [string]$key) {
    $i = Find-EnvLine $envFile $key
    if ($i -lt 0) { return $null }
    $line = $envFile.Lines[$i]
    return $line.Substring($line.IndexOf('=') + 1).Trim()
}

function Set-EnvValue($envFile, [string]$key, [string]$value) {
    $i = Find-EnvLine $envFile $key
    if ($i -lt 0) { $envFile.Lines.Add("$key=$value") }
    else { $envFile.Lines[$i] = "$key=$value" }
    if (-not $envFile.Changed.Contains($key)) { $envFile.Changed.Add($key) }
}

# Sets $key only when it is still a placeholder. Returns $true if it did.
function Set-IfPlaceholder($envFile, [string]$key, [string]$value) {
    $current = Get-EnvValue $envFile $key
    if (-not (Test-Placeholder $current)) { return $false }
    if ($current -eq $value) { return $false }
    Set-EnvValue $envFile $key $value
    return $true
}

function Save-EnvFile($envFile) {
    if ($envFile.Changed.Count -eq 0) { return }
    $text = ($envFile.Lines -join $envFile.NL) + $envFile.NL
    # UTF-8 without a BOM: a BOM would become part of the first key's name.
    [IO.File]::WriteAllText($envFile.Path, $text, (New-Object System.Text.UTF8Encoding($false)))
}

# The password segment of scheme://user:PASSWORD@host, URL-decoded.
function Get-UrlPassword([string]$url, [string]$user) {
    if (-not $url) { return $null }
    $m = [regex]::Match($url, '://' + [regex]::Escape($user) + ':([^@]*)@')
    if (-not $m.Success) { return $null }
    return [Uri]::UnescapeDataString($m.Groups[1].Value)
}

function Set-UrlPassword([string]$url, [string]$user, [string]$password) {
    $m = [regex]::Match($url, '://' + [regex]::Escape($user) + ':([^@]*)@')
    if (-not $m.Success) { return $url }
    $g = $m.Groups[1]
    return $url.Substring(0, $g.Index) + [Uri]::EscapeDataString($password) + $url.Substring($g.Index + $g.Length)
}

# -- 1. tools ------------------------------------------------------------------

function Test-Tools {
    Write-Step 1 'Checking tools...'
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw 'git is not installed. Install it from https://git-scm.com and run this again.'
    }
    Write-Host '  ok    git'
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker is not installed. Install Docker Desktop and run this again.'
    }
    Write-Host '  ok    docker'
}

# -- 2. clone ------------------------------------------------------------------

function Invoke-Clone {
    Write-Step 2 "Cloning repos into $Root ..."
    foreach ($name in $Repos.Keys) {
        $dir = Join-Path $Root $name
        if (Test-Path $dir) {
            Write-Host "  skip  $name (already there)"
            continue
        }
        $branch = $Repos[$name]
        Write-Host "  clone $name ($branch)"
        git clone --quiet --branch $branch "$GitBase/$name.git" $dir
        if ($LASTEXITCODE -ne 0) { throw "git clone failed for $name. Check the output above." }
    }
}

# -- 3. .env files ---------------------------------------------------------------

function New-EnvFiles {
    Write-Step 3 'Creating missing .env files...'
    $found = @()
    foreach ($name in @('devboard-infra') + @($Repos.Keys)) {
        $dir = Join-Path $Root $name
        $example = Join-Path $dir '.env.example'
        $target = Join-Path $dir '.env'
        if (-not (Test-Path $example)) { continue }
        if (Test-Path $target) {
            Write-Host "  skip  $name\.env (already there)"
        } else {
            Copy-Item $example $target
            Write-Host "  new   $name\.env"
        }
        $found += $name
    }
    return $found
}

# -- 4. secrets ------------------------------------------------------------------

function Set-Secrets([string[]]$names) {
    Write-Step 4 'Filling in secrets...'

    $envs = [ordered]@{}
    foreach ($name in $names) { $envs[$name] = Read-EnvFile (Join-Path (Join-Path $Root $name) '.env') }
    $infra = $envs['devboard-infra']

    # Admin logins for the infra containers.
    foreach ($key in @('POSTGRES_USER', 'MONGO_ROOT_USER', 'MINIO_ROOT_USER')) {
        [void](Set-IfPlaceholder $infra $key 'devboard_admin')
    }
    foreach ($key in @('POSTGRES_PASSWORD', 'MONGO_ROOT_PASSWORD', 'MINIO_ROOT_PASSWORD')) {
        [void](Set-IfPlaceholder $infra $key (New-Secret 16))
    }

    # Per-service DB passwords: one value, written everywhere it appears.
    foreach ($db in $DbPasswords) {
        $svc = $envs[$db.Service]
        if ($null -eq $svc) { continue }

        # Every real value already present, infra first so it wins on a tie.
        $real = @()
        $v = Get-EnvValue $infra $db.InfraKey
        if (-not (Test-Placeholder $v)) { $real += $v }
        foreach ($k in $db.Keys) {
            $v = Get-EnvValue $svc $k
            if (-not (Test-Placeholder $v)) { $real += $v }
        }
        foreach ($k in $db.UrlKeys) {
            $v = Get-UrlPassword (Get-EnvValue $svc $k) $db.User
            if (-not (Test-Placeholder $v)) { $real += $v }
        }

        $distinct = @($real | Select-Object -Unique)
        if ($distinct.Count -gt 1) {
            Write-Warn "$($db.User): the password differs between devboard-infra\.env ($($db.InfraKey)) and $($db.Service)\.env. Left as is - make them match by hand."
        }
        if ($distinct.Count -gt 0) { $password = $distinct[0] } else { $password = New-Secret 16 }

        [void](Set-IfPlaceholder $infra $db.InfraKey $password)
        foreach ($k in $db.Keys) { [void](Set-IfPlaceholder $svc $k $password) }
        foreach ($k in $db.UrlKeys) {
            $url = Get-EnvValue $svc $k
            if ($null -eq $url) { continue }
            if (Test-Placeholder (Get-UrlPassword $url $db.User)) {
                Set-EnvValue $svc $k (Set-UrlPassword $url $db.User $password)
            }
        }
    }

    # JWT_SECRET and INTERNAL_API_KEY: one value across every service.
    foreach ($key in $SharedSecrets) {
        $holders = @($envs.Keys | Where-Object { $_ -ne 'devboard-infra' -and (Find-EnvLine $envs[$_] $key) -ge 0 })
        $real = @($holders | ForEach-Object { Get-EnvValue $envs[$_] $key } | Where-Object { -not (Test-Placeholder $_) })
        $groups = @($real | Group-Object -CaseSensitive | Sort-Object Count -Descending)
        if ($groups.Count -gt 1) {
            $odd = @($holders | Where-Object { (Get-EnvValue $envs[$_] $key) -ne $groups[0].Name -and -not (Test-Placeholder (Get-EnvValue $envs[$_] $key)) })
            Write-Warn "$key is not the same in every service. These differ from the rest: $($odd -join ', '). Left as is - make them match by hand."
        }
        if ($groups.Count -gt 0) { $value = $groups[0].Name } else { $value = New-Secret 32 }
        foreach ($name in $holders) { [void](Set-IfPlaceholder $envs[$name] $key $value) }
    }

    # Django SECRET_KEY: per service, nothing else needs to know it.
    foreach ($name in @('devboard-core', 'devboard-work')) {
        if ($envs[$name]) { [void](Set-IfPlaceholder $envs[$name] 'SECRET_KEY' (New-Secret 32)) }
    }

    # Attachments talks to MinIO with the MinIO admin login.
    $att = $envs['devboard-attachments']
    if ($att) {
        [void](Set-IfPlaceholder $att 'S3_ACCESS_KEY' (Get-EnvValue $infra 'MINIO_ROOT_USER'))
        [void](Set-IfPlaceholder $att 'S3_SECRET_KEY' (Get-EnvValue $infra 'MINIO_ROOT_PASSWORD'))
        # MinIO's host port moved 9000 -> 19000 so it can't clash with another
        # project's MinIO. The browser uploads to this address directly.
        if ((Get-EnvValue $att 'S3_PUBLIC_ENDPOINT_URL') -eq 'http://localhost:9000') {
            Set-EnvValue $att 'S3_PUBLIC_ENDPOINT_URL' 'http://localhost:19000'
        }
    }

    # Plain defaults that are the same on every machine.
    if ($envs['devboard-auth']) {
        [void](Set-IfPlaceholder $envs['devboard-auth'] 'FRONTEND_URL' $FrontendUrl)
        [void](Set-IfPlaceholder $envs['devboard-auth'] 'TRUSTED_PROXY_IPS' '')
    }
    if ($envs['devboard-email']) {
        [void](Set-IfPlaceholder $envs['devboard-email'] 'APP_URL' $FrontendUrl)
    }

    return $envs
}

# -- 5. your accounts --------------------------------------------------------------

function Read-Setting($field) {
    $hint = 'Enter to skip'
    if ($field.Default) { $hint = "Enter for $($field.Default)" }
    $prompt = "  $($field.Label) [$hint]"
    while ($true) {
        if ($field.Secret) {
            # Typed hidden, so it never shows on screen or in a screen share.
            $secure = Read-Host $prompt -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $value = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        } else {
            $value = Read-Host $prompt
        }
        $value = "$value".Trim()
        if (-not $value -and $field.Default) { $value = $field.Default }
        if (-not $value -or -not $field.Pattern -or $value -match $field.Pattern) { return $value }
        Write-Warn 'That does not look right, try again.'
    }
}

# Quotes a value only when it needs it. Single quotes keep it literal for both
# Docker's env_file and python-dotenv (no # comments, no $ expansion).
function Format-EnvValue([string]$value) {
    if ($value -match '^[A-Za-z0-9._@:/+=,-]*$') { return $value }
    if (-not $value.Contains("'")) { return "'" + $value + "'" }
    return '"' + ($value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Read-AccountSettings($envs) {
    Write-Step 5 'Your accounts (press Enter to skip any of these)...'
    $asked = $false
    foreach ($group in $AccountSettings) {
        $e = $envs[$group.Service]
        if ($null -eq $e) { continue }
        $todo = @($group.Fields | Where-Object { Test-Placeholder (Get-EnvValue $e $_.Key) })
        if ($todo.Count -eq 0) { continue }

        $asked = $true
        Write-Host ''
        Write-Host "  $($group.Title)"
        $first = $true
        foreach ($field in $todo) {
            $value = Read-Setting $field
            if (-not $value) {
                if ($first) { Write-Host '  skip  (fill in later)'; break }
                continue
            }
            $first = $false
            Set-EnvValue $e $field.Key (Format-EnvValue $value)
        }
    }
    if (-not $asked) { Write-Host '  ok    nothing to ask, all set already' }
}

# Save every .env; report key names only - never values.
function Save-EnvFiles($envs) {
    Write-Host ''
    $left = @()
    foreach ($name in $envs.Keys) {
        $e = $envs[$name]
        Save-EnvFile $e
        if ($e.Changed.Count -gt 0) { Write-Host "  set   $name\.env: $($e.Changed -join ', ')" }
        else { Write-Host "  ok    $name\.env (nothing to fill)" }
        foreach ($line in $e.Lines) {
            if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$') {
                $k = $Matches[1]
                if ($EmptyAllowed -contains $k) { continue }
                if (Test-Placeholder $Matches[2]) { $left += "$name\.env: $k" }
            }
        }
    }
    return $left
}

# -- 5. start --------------------------------------------------------------------

function Start-Stack {
    Write-Step 6 'Starting DevBoard...'
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Warn 'Docker is not running. Start Docker Desktop, then run bootstrap.bat again.'
        return $false
    }
    $answer = Read-Host '  Build and start everything now? This takes a few minutes the first time. [Y/n]'
    if ($answer -match '^(n|no)$') {
        Write-Host '  skip  Start it later with: docker compose -f devboard-infra\stack.yml up -d --build'
        return $false
    }
    docker network inspect devboard-ic-network *> $null
    if ($LASTEXITCODE -ne 0) { docker network create devboard-ic-network | Out-Null }
    docker compose -f (Join-Path $InfraDir 'stack.yml') up -d --build
    if ($LASTEXITCODE -ne 0) { throw 'docker compose failed. Check the output above.' }
    return $true
}

# -- main --------------------------------------------------------------------------

try {
    Write-Host ''
    Write-Host '============================================================'
    Write-Host ' DevBoard bootstrap'
    Write-Host '============================================================'

    Test-Tools
    Invoke-Clone
    $names = New-EnvFiles
    $envs = Set-Secrets $names
    if ($NoPrompt) { Write-Step 5 'Skipped (-NoPrompt).' }
    else { Read-AccountSettings $envs }
    $left = Save-EnvFiles $envs

    $started = $false
    if ($NoStart) { Write-Step 6 'Skipped (-NoStart).' }
    else { $started = Start-Stack }

    Write-Host ''
    Write-Host '============================================================'
    if ($left.Count -gt 0) {
        Write-Host ' Fill these in by hand (your own accounts - no default):' -ForegroundColor Yellow
        foreach ($item in $left) { Write-Host "   $item" }
        Write-Host ' Then restart the service that uses it: redeploy.bat'
        Write-Host ' (Or run bootstrap.bat again - it asks only for what is still missing.)'
        Write-Host ''
    }
    if ($started) {
        Write-Host ' DevBoard is starting: http://localhost:8443'
        Write-Host ' Migrations are done when every migrate-* row says "Exited (0)":'
        Write-Host '   docker compose -f devboard-infra\stack.yml ps -a'
    }
    Write-Host '============================================================'
    exit 0
}
catch {
    Write-Host ''
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
