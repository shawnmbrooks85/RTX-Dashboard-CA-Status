#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstallPath  = 'C:\RTX-Dashboard-CA-Status',
    [string]$SourcePath   = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$webTaskName     = 'CA-Dashboard-WebServer'
$collectTaskName = 'CA-Dashboard-DataCollect'
$sourceRoot      = Split-Path $PSScriptRoot -Parent

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Certificate Status Dashboard -- Update        |" -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Source : $sourceRoot" -ForegroundColor DarkGray
Write-Host "  Target : $InstallPath" -ForegroundColor DarkGray
Write-Host ""

if (-not (Test-Path $InstallPath)) {
    Write-Host "  [FAIL] Install path not found. Run Setup-CACertDashboard.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "  [1/4] Stopping web server task..." -ForegroundColor Cyan
Stop-ScheduledTask -TaskName $webTaskName -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "    Stopped." -ForegroundColor DarkGray

Write-Host ""
Write-Host "  [2/4] Updating web files..." -ForegroundColor Cyan

$webFiles = @('index.html', 'app.js', 'cacert.js', 'styles.css', 'rtx_logo.svg', 'faq.html')
foreach ($f in $webFiles) {
    $src = Join-Path $sourceRoot $f
    $dst = Join-Path $InstallPath $f
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "    Updated: $f" -ForegroundColor DarkGray
    }
}

$scripts = @('Collect-CACertData.ps1', 'Setup-CACertDashboard.ps1', 'Remove-CACertDashboard.ps1', 'Update-CACertDashboard.ps1')
foreach ($s in $scripts) {
    $src = Join-Path $PSScriptRoot $s
    $dst = Join-Path $InstallPath "scripts\$s"
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $dst -Force
        Write-Host "    Updated: scripts\$s" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  [3/4] Running data collection..." -ForegroundColor Cyan

$collectScript = Join-Path $InstallPath 'scripts\Collect-CACertData.ps1'
$dataPath      = Join-Path $InstallPath 'data\ca_data.json'
try {
    & $collectScript -OutputPath $dataPath
} catch {
    Write-Host "    [WARN] Collection failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  [4/4] Restarting web server task..." -ForegroundColor Cyan
Start-ScheduledTask -TaskName $webTaskName -ErrorAction SilentlyContinue
Write-Host "    $webTaskName started." -ForegroundColor DarkGray

Write-Host ""
Write-Host "  Task health:" -ForegroundColor Cyan
foreach ($taskName in @($webTaskName, $collectTaskName)) {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) {
        $info = $t | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue
        Write-Host ("    {0,-40} State:{1,-12} LastResult:{2}" -f $taskName, $t.State, $info.LastTaskResult) -ForegroundColor DarkGray
    } else {
        Write-Host "    [WARN] $taskName not found" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "  Update complete." -ForegroundColor Green
Write-Host ""
