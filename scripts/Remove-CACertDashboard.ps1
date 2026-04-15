#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$InstallPath  = 'C:\RTX-Dashboard-CA-Status',
    [int]$DashboardPort   = 8089
)

$ErrorActionPreference = 'Stop'

$webTaskName     = 'CA-Dashboard-WebServer'
$collectTaskName = 'CA-Dashboard-DataCollect'

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Certificate Status Dashboard -- Removal      |" -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Install path : $InstallPath" -ForegroundColor DarkGray
Write-Host "  Port         : $DashboardPort" -ForegroundColor DarkGray
Write-Host ""

$confirm = Read-Host "  Remove CA Certificate Status Dashboard? [y/N]"
if ($confirm -notmatch '^[Yy]') {
    Write-Host "  Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host ""
Write-Host "  [1/4] Stopping and removing scheduled tasks..." -ForegroundColor Cyan

foreach ($taskName in @($webTaskName, $collectTaskName)) {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "    Removed: $taskName" -ForegroundColor DarkGray
    } else {
        Write-Host "    Not found: $taskName" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "  [2/4] Removing firewall rule..." -ForegroundColor Cyan

netsh advfirewall firewall delete rule name="CA-Dashboard-Port-$DashboardPort" 2>$null | Out-Null
Write-Host "    Firewall rule removed (if existed)" -ForegroundColor DarkGray

Write-Host ""
Write-Host "  [3/4] Removing SSL certificate binding..." -ForegroundColor Cyan

$sslDump = netsh http show sslcert ipport=0.0.0.0:$DashboardPort 2>&1 | Out-String
if ($sslDump -match 'Certificate Hash\s*:\s*([0-9a-fA-F]+)') {
    $thumbprint = $Matches[1]
    netsh http delete sslcert ipport=0.0.0.0:$DashboardPort 2>$null | Out-Null
    Write-Host "    SSL binding removed from port $DashboardPort" -ForegroundColor DarkGray
    $cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -ieq $thumbprint } | Select-Object -First 1
    if ($cert -and $cert.FriendlyName -like 'CA Dashboard*') {
        $otherPorts = netsh http show sslcert 2>&1 | Select-String 'Certificate Hash' | ForEach-Object { $_.Line -replace '.*:\s*','' -replace '\s','' }
        if ($thumbprint -notin $otherPorts) {
            Remove-Item "Cert:\LocalMachine\My\$thumbprint" -Force -ErrorAction SilentlyContinue
            Remove-Item "Cert:\LocalMachine\Root\$thumbprint" -Force -ErrorAction SilentlyContinue
            Write-Host "    Certificate removed from stores" -ForegroundColor DarkGray
        }
    }
} else {
    Write-Host "    No SSL binding found on port $DashboardPort" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  [4/4] Removing install directory..." -ForegroundColor Cyan

if (Test-Path $InstallPath) {
    Remove-Item -Path $InstallPath -Recurse -Force
    Write-Host "    Removed: $InstallPath" -ForegroundColor DarkGray
} else {
    Write-Host "    Not found: $InstallPath" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  CA Certificate Status Dashboard removed." -ForegroundColor Green
Write-Host ""
