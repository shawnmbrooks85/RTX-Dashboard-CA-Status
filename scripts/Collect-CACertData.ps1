#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [string]$OutputPath = 'C:\RTX-Dashboard-CA-Status\data\ca_data.json'
)

$ErrorActionPreference = 'Stop'
$outputDir = Split-Path $OutputPath -Parent

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Certificate Status -- Data Collector          |" -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Output : $OutputPath" -ForegroundColor DarkGray
Write-Host ""

$now = Get-Date

function Get-CertStatus($daysLeft) {
    if ($daysLeft -lt 0)  { return 'expired' }
    if ($daysLeft -lt 15) { return 'critical' }
    if ($daysLeft -lt 60) { return 'warning' }
    return 'valid'
}

$casResult  = @()
$selfSigned = @()
$entSummary = @{ total=0; valid=0; warning=0; critical=0; expired=0; unreachable=0 }
$ssSummary  = @{ total=0; valid=0; warning=0; critical=0; expired=0 }

Write-Host "  [1/3] Enumerating Enterprise CAs from Active Directory..." -ForegroundColor Cyan

$caList = @()
try {
    $tcaOut = certutil -TCAInfo 2>&1 | Out-String
    $blocks = $tcaOut -split '(?m)^\s*$' | Where-Object { $_ -match '\\' }
    foreach ($block in $blocks) {
        $configMatch = [regex]::Match($block, '(?im)^\s*Config:\s*(.+)')
        $nameMatch   = [regex]::Match($block, '(?im)^\s*[\w ]*Name\s*:\s*(.+)')
        if ($configMatch.Success) {
            $config = $configMatch.Groups[1].Value.Trim().Trim('"')
            $cname  = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $config.Split('\')[-1] }
            if ($config -match '\\') {
                $caList += @{ Config = $config; Name = $cname }
            }
        }
    }
} catch {
    Write-Host "    [WARN] certutil -TCAInfo failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

if ($caList.Count -eq 0) {
    try {
        $caLocator = New-Object -ComObject CertificateAuthority.Config
        $config    = $caLocator.GetConfig(0)
        if ($config -match '\\') {
            $caList += @{ Config = $config; Name = $config.Split('\')[-1] }
        }
    } catch {
        Write-Host "    [WARN] CertificateAuthority.Config COM also failed" -ForegroundColor Yellow
    }
}

Write-Host "    Found $($caList.Count) Enterprise CA(s)" -ForegroundColor DarkGray

foreach ($ca in $caList) {
    $caConfig = $ca.Config
    $caName   = $ca.Name
    $caEntry  = @{
        caName        = $caName
        caConfig      = $caConfig
        reachable     = $false
        subject       = $null
        issuer        = $null
        thumbprint    = $null
        notAfter      = $null
        daysRemaining = $null
        status        = 'unreachable'
    }

    try {
        $pingOut = certutil -config $caConfig -ping 2>&1 | Out-String
        if ($pingOut -match 'interface is alive') { $caEntry.reachable = $true }
    } catch {}

    if ($caEntry.reachable) {
        try {
            $caInfoOut  = certutil -config $caConfig -CAInfo 2>&1 | Out-String
            $naMatch    = [regex]::Match($caInfoOut, '(?i)NotAfter\s*=\s*(.+)')
            if ($naMatch.Success) {
                $expStr = $naMatch.Groups[1].Value.Trim()
                try {
                    $expDate = [datetime]::Parse($expStr)
                    $days    = [math]::Floor(($expDate - $now).TotalDays)
                    $caEntry.notAfter      = $expDate.ToString('yyyy-MM-dd')
                    $caEntry.daysRemaining = $days
                    $caEntry.status        = Get-CertStatus $days
                } catch {}
            }
            $subjMatch  = [regex]::Match($caInfoOut, '(?im)^\s*Subject\s*:\s*(.+)')
            $issMatch   = [regex]::Match($caInfoOut, '(?im)^\s*Issuer\s*:\s*(.+)')
            $thumbMatch = [regex]::Match($caInfoOut, '(?im)Cert\s*Hash.*?:\s*([0-9a-fA-F\s]+)')
            if ($subjMatch.Success)  { $caEntry.subject    = $subjMatch.Groups[1].Value.Trim() }
            if ($issMatch.Success)   { $caEntry.issuer     = $issMatch.Groups[1].Value.Trim() }
            if ($thumbMatch.Success) { $caEntry.thumbprint = $thumbMatch.Groups[1].Value -replace '\s','' }
        } catch {
            Write-Host "    [WARN] certutil -CAInfo failed for $caConfig" -ForegroundColor Yellow
        }
    }

    if ($null -eq $caEntry.daysRemaining) {
        foreach ($storeName in @('CA','Root')) {
            $found = Get-ChildItem "Cert:\LocalMachine\$storeName" -ErrorAction SilentlyContinue |
                Where-Object { $_.Subject -match [regex]::Escape($caName) -or $_.Issuer -match [regex]::Escape($caName) } |
                Sort-Object NotAfter -Descending | Select-Object -First 1
            if ($found) {
                $days = [math]::Floor(($found.NotAfter - $now).TotalDays)
                $caEntry.subject       = $found.Subject
                $caEntry.issuer        = $found.Issuer
                $caEntry.thumbprint    = $found.Thumbprint
                $caEntry.notAfter      = $found.NotAfter.ToString('yyyy-MM-dd')
                $caEntry.daysRemaining = $days
                $caEntry.status        = Get-CertStatus $days
                break
            }
        }
    }

    $entSummary.total++
    $entSummary[$caEntry.status]++
    $casResult += $caEntry
    $statusColor = if (@{ valid='Green'; warning='Yellow'; critical='Red'; expired='Red'; unreachable='DarkYellow' }[$caEntry.status]) { @{ valid='Green'; warning='Yellow'; critical='Red'; expired='Red'; unreachable='DarkYellow' }[$caEntry.status] } else { 'Gray' }
    $notAfterDisplay = if ($caEntry.notAfter) { $caEntry.notAfter } else { '-' }
    Write-Host ("    [{0,-12}] {1,-40} Expires: {2}" -f $caEntry.status.ToUpper(), $caName, $notAfterDisplay) -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "  [2/3] Scanning local cert stores for self-signed certs..." -ForegroundColor Cyan

$seenThumbs = @{}
foreach ($storeName in @('My','CA','Root')) {
    $certs = Get-ChildItem "Cert:\LocalMachine\$storeName" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Subject -eq $_.Issuer -and
            $_.Subject -ne '' -and
            $_.Issuer -notmatch 'SMS_SiteCode|SMSI'
        }
    foreach ($cert in $certs) {
        if ($seenThumbs.ContainsKey($cert.Thumbprint)) { continue }
        $seenThumbs[$cert.Thumbprint] = $true
        $days   = [math]::Floor(($cert.NotAfter - $now).TotalDays)
        $status = Get-CertStatus $days
        $ssSummary.total++
        $ssSummary[$status]++
        $selfSigned += @{
            friendlyName  = if ($cert.FriendlyName) { $cert.FriendlyName } else { $cert.Subject -replace 'CN=','' -replace ',.*','' }
            subject       = $cert.Subject
            store         = $storeName
            thumbprint    = $cert.Thumbprint
            serialNumber  = $cert.SerialNumber
            notAfter      = $cert.NotAfter.ToString('yyyy-MM-dd')
            daysRemaining = $days
            status        = $status
        }
    }
}
Write-Host "    Self-signed: $($selfSigned.Count) found" -ForegroundColor DarkGray

$payload = @{
    collectedAt       = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    enterpriseSummary = $entSummary
    selfSignedSummary = $ssSummary
    cas               = [object[]]$casResult
    selfSigned        = [object[]]$selfSigned
}

$wrapper = @{ caCertExpiry = $payload }

Write-Host ""
Write-Host "  [3/3] Writing data..." -ForegroundColor Cyan

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$retries = 10
$json    = $wrapper | ConvertTo-Json -Depth 10
$tmp     = Join-Path $outputDir ("ca_data_" + [guid]::NewGuid().ToString('N').Substring(0,8) + ".tmp")
while ($retries -gt 0) {
    try {
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
        Move-Item -Path $tmp -Destination $OutputPath -Force
        break
    } catch {
        $retries--
        if ($retries -eq 0) { throw }
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "    Written to: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "  Enterprise CAs : $($entSummary.total)  (Valid:$($entSummary.valid)  Warn:$($entSummary.warning)  Critical:$($entSummary.critical)  Expired:$($entSummary.expired)  Unreachable:$($entSummary.unreachable))" -ForegroundColor Cyan
Write-Host "  Self-signed    : $($ssSummary.total)  (Valid:$($ssSummary.valid)  Warn:$($ssSummary.warning)  Critical:$($ssSummary.critical)  Expired:$($ssSummary.expired))" -ForegroundColor Cyan
Write-Host ""
