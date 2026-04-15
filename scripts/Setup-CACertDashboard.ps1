#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstallPath    = 'C:\RTX-Dashboard-CA-Status',
    [int]$DashboardPort     = 8089,
    [int]$CollectInterval   = 60,
    [string]$TaskAccount    = 'SYSTEM',
    [string]$TaskPassword   = '',
    [string]$SourcePath     = $PSScriptRoot,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$webTaskName     = 'CA-Dashboard-WebServer'
$collectTaskName = 'CA-Dashboard-DataCollect'
$servePath       = Join-Path $InstallPath 'scripts\serve.ps1'
$collectPath     = Join-Path $InstallPath 'scripts\Collect-CACertData.ps1'
$dataDir         = Join-Path $InstallPath 'data'
$certScript      = Join-Path $PSScriptRoot 'Request-CACert.ps1'

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Certificate Status Dashboard -- Setup         |" -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Install path  : $InstallPath" -ForegroundColor DarkGray
Write-Host "  Port          : $DashboardPort" -ForegroundColor DarkGray
Write-Host "  Task account  : $TaskAccount" -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "  Proceed with setup? [Y]"
    if ($confirm -match '^[Nn]') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

$UsePassword = $false

if (-not $Force) {
    Write-Host ""
    Write-Host "  +-- Scheduled Task Credentials ----------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |  Tasks default to SYSTEM (machine account) -- suitable for most     |" -ForegroundColor DarkGray
    Write-Host "  |  member-server deployments. Press Enter to accept this default.      |" -ForegroundColor DarkGray
    Write-Host "  |                                                                      |" -ForegroundColor DarkGray
    Write-Host "  |  NOTE: If your Enterprise CA is hosted on a Domain Controller        |" -ForegroundColor Yellow
    Write-Host "  |  (DC) locked down to Domain Admin accounts, SYSTEM will be           |" -ForegroundColor Yellow
    Write-Host "  |  blocked from issuing certutil RPC queries. In that case supply a    |" -ForegroundColor Yellow
    Write-Host "  |  DA-privileged service account (e.g. DOMAIN\SVC-CA-Reader).          |" -ForegroundColor Yellow
    Write-Host "  +----------------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
    $acctInput = Read-Host "  Task account [SYSTEM]"
    if (-not [string]::IsNullOrWhiteSpace($acctInput)) {
        $TaskAccount  = $acctInput.Trim()
        $ss           = Read-Host "  Password for $TaskAccount" -AsSecureString
        $TaskPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss))
        $UsePassword  = $true
        Write-Host "    Account set: $TaskAccount" -ForegroundColor DarkGray
    } else {
        Write-Host "    Using default: SYSTEM" -ForegroundColor DarkGray
    }
} elseif ($TaskAccount -ne 'SYSTEM' -and $TaskPassword -ne '') {
    $UsePassword = $true
}

if (-not $Force) {
    Write-Host ""
    Write-Host "  +-- Data Collection Interval ----------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |  How often the CA data collector runs. CA certificate        |" -ForegroundColor DarkGray
    Write-Host "  |  expiry is slow-moving -- 60 minutes is the recommended      |" -ForegroundColor DarkGray
    Write-Host "  |  default. Press Enter to accept, or enter a custom value.    |" -ForegroundColor DarkGray
    Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
    $intervalInput = Read-Host "  Collect interval in minutes [$CollectInterval]"
    if (-not [string]::IsNullOrWhiteSpace($intervalInput)) {
        $parsed = 0
        if ([int]::TryParse($intervalInput.Trim(), [ref]$parsed) -and $parsed -gt 0) {
            $CollectInterval = $parsed
        } else {
            Write-Host "    [WARN] Invalid value -- keeping default of $CollectInterval min" -ForegroundColor Yellow
        }
    }
    Write-Host "    Collect interval: $CollectInterval minute(s)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  Collect every : $CollectInterval minute(s)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [1/6] Creating install directory..." -ForegroundColor Cyan

$dirs = @($InstallPath, $dataDir, (Join-Path $InstallPath 'scripts'))
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Write-Host "    Created: $d" -ForegroundColor DarkGray
    } else {
        Write-Host "    Exists:  $d" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  [2/6] Copying dashboard files..." -ForegroundColor Cyan

$sourceRoot = if (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'index.html')) {
    Split-Path $PSScriptRoot -Parent
} else {
    $PSScriptRoot
}

$filesToCopy = @(
    'index.html',
    'app.js',
    'cacert.js',
    'styles.css',
    'rtx_logo.svg',
    'faq.html'
)
foreach ($f in $filesToCopy) {
    $src = Join-Path $sourceRoot $f
    $dst = Join-Path $InstallPath $f
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "    Copied: $f" -ForegroundColor DarkGray
    } else {
        Write-Host "    [WARN] Not found: $f" -ForegroundColor Yellow
    }
}

$scripts = @('Collect-CACertData.ps1', 'serve.ps1', 'Request-CACert.ps1', 'New-DashboardCert.ps1', 'Remove-CACertDashboard.ps1', 'Update-CACertDashboard.ps1')
foreach ($s in $scripts) {
    $src = Join-Path $PSScriptRoot $s
    $dst = Join-Path $InstallPath "scripts\$s"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "    Copied: scripts\$s" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  [3/6] Configuring serve.ps1 for port $DashboardPort..." -ForegroundColor Cyan

$serveContent = Get-Content $servePath -Raw
$serveContent = $serveContent -replace "^\`$root\s*=\s*'.*'", "`$root    = '$InstallPath'"
$serveContent = $serveContent -replace "^\`$port\s*=\s*\d+", "`$port    = $DashboardPort"
[System.IO.File]::WriteAllText($servePath, $serveContent, [System.Text.Encoding]::UTF8)
Write-Host "    serve.ps1 configured" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  [4/6] SSL certificate..." -ForegroundColor Cyan

Write-Host "    Select certificate type:" -ForegroundColor White
Write-Host "      [1] Self-signed certificate (works immediately, local trust only)" -ForegroundColor DarkGray
Write-Host "      [2] Enterprise CA certificate (trusted by all domain machines) [RECOMMENDED]" -ForegroundColor Green
Write-Host ""
if ($Force) { $certChoice = '1' } else {
    $certChoice = Read-Host "    Certificate type [2]"
    if ([string]::IsNullOrWhiteSpace($certChoice)) { $certChoice = '2' }
}

if ($certChoice -eq '2') {
    $caScript = Join-Path $PSScriptRoot 'Request-CACert.ps1'
    if (Test-Path $caScript) {
        try {
            & $caScript -DashboardPort $DashboardPort
        } catch {
            Write-Host "    [WARN] CA cert setup failed: $($_.Exception.Message). Dashboard will use HTTP." -ForegroundColor Yellow
        }
    } else {
        Write-Host "    [WARN] Request-CACert.ps1 not found. Falling back to HTTP." -ForegroundColor Yellow
    }
} else {
    $selfSignedScript = Join-Path $PSScriptRoot 'New-DashboardCert.ps1'
    if (Test-Path $selfSignedScript) {
        try {
            Write-Host "    Creating self-signed certificate..." -ForegroundColor DarkGray
            & $selfSignedScript -HttpsPort $DashboardPort -Force
        } catch {
            Write-Host "    [WARN] Self-signed cert setup failed: $($_.Exception.Message). Dashboard will use HTTP." -ForegroundColor Yellow
        }
    } else {
        Write-Host "    [SKIP] New-DashboardCert.ps1 not found. Configure SSL manually." -ForegroundColor DarkYellow
    }
}

Write-Host ""
Write-Host "  [5/6] Registering scheduled tasks..." -ForegroundColor Cyan

$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

foreach ($taskName in @($webTaskName, $collectTaskName)) {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "    Removed existing task: $taskName" -ForegroundColor DarkGray
    }
}

$webAction   = New-ScheduledTaskAction -Execute $psExe -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$servePath`""
$webTrigger  = New-ScheduledTaskTrigger -AtStartup
$webSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
if ($UsePassword) {
    $webPrincipal = New-ScheduledTaskPrincipal -UserId $TaskAccount -LogonType Password -RunLevel Highest
    Register-ScheduledTask -TaskName $webTaskName -Action $webAction -Trigger $webTrigger -Settings $webSettings -Principal $webPrincipal -Password $TaskPassword -Force | Out-Null
} else {
    $webPrincipal = New-ScheduledTaskPrincipal -UserId $TaskAccount -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $webTaskName -Action $webAction -Trigger $webTrigger -Settings $webSettings -Principal $webPrincipal -Force | Out-Null
}
Write-Host "    Registered: $webTaskName ($TaskAccount)" -ForegroundColor DarkGray

$collectArg      = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$collectPath`" -OutputPath `"$dataDir\ca_data.json`""
$collectAction   = New-ScheduledTaskAction -Execute $psExe -Argument $collectArg
$collectTriggers = @(
    (New-ScheduledTaskTrigger -AtStartup),
    (New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes $CollectInterval) -Once -At (Get-Date))
)
$collectSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2)
if ($UsePassword) {
    $collectPrincipal = New-ScheduledTaskPrincipal -UserId $TaskAccount -LogonType Password -RunLevel Highest
    Register-ScheduledTask -TaskName $collectTaskName -Action $collectAction -Trigger $collectTriggers -Settings $collectSettings -Principal $collectPrincipal -Password $TaskPassword -Force | Out-Null
} else {
    $collectPrincipal = New-ScheduledTaskPrincipal -UserId $TaskAccount -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $collectTaskName -Action $collectAction -Trigger $collectTriggers -Settings $collectSettings -Principal $collectPrincipal -Force | Out-Null
}
Write-Host "    Registered: $collectTaskName ($TaskAccount, every $CollectInterval min)" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  [6/6] Starting tasks and running initial data collection..." -ForegroundColor Cyan

try {
    & $collectPath -OutputPath "$dataDir\ca_data.json"
} catch {
    Write-Host "    [WARN] Initial collection failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Start-ScheduledTask -TaskName $webTaskName -ErrorAction SilentlyContinue
Write-Host "    Web server task started" -ForegroundColor DarkGray

try {
    $url = "http://$($env:COMPUTERNAME):$DashboardPort"
    netsh advfirewall firewall add rule name="CA-Dashboard-Port-$DashboardPort" dir=in action=allow protocol=TCP localport=$DashboardPort | Out-Null
    Write-Host "    Firewall rule added for port $DashboardPort" -ForegroundColor DarkGray
} catch {}

$sslCheck = netsh http show sslcert ipport=0.0.0.0:$DashboardPort 2>&1 | Out-String
$protocol = if ($sslCheck -match 'Certificate Hash') { 'https' } else { 'http' }

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |  SETUP COMPLETE                                        |" -ForegroundColor Green
Write-Host "  +--------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  Dashboard  : ${protocol}://$($env:COMPUTERNAME):$DashboardPort" -ForegroundColor White
Write-Host "  |  Data file  : $dataDir\ca_data.json" -ForegroundColor DarkGray
Write-Host "  |  Collector  : $collectTaskName (every $CollectInterval min)" -ForegroundColor DarkGray
Write-Host "  |  Web task   : $webTaskName" -ForegroundColor DarkGray
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
