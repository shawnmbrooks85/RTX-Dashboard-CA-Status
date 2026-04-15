#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [int]$DashboardPort,
    [string]$TemplateName,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Status Dashboard -- Enterprise CA Setup       |" -ForegroundColor DarkCyan
Write-Host "  |   (Network-Agnostic Enrollment)                        |" -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""

Write-Host "  [1/8] DETECTING SERVER INFORMATION" -ForegroundColor Cyan

$hostName = $env:COMPUTERNAME
$domain   = (Get-WmiObject Win32_ComputerSystem).Domain
$fqdn     = "${hostName}.${domain}"

Write-Host "    Hostname  : $hostName" -ForegroundColor DarkGray
Write-Host "    Domain    : $domain" -ForegroundColor DarkGray
Write-Host "    FQDN      : $fqdn" -ForegroundColor DarkGray

Write-Host ""

Write-Host "  [2/8] DETECTING EXISTING DASHBOARD BINDINGS" -ForegroundColor Cyan

$portBindings = @{}
$sslDump = netsh http show sslcert 2>&1 | Out-String
$sslSections = $sslDump -split '(?=\s*IP:port\s*:|\s*Hostname:port\s*:)'

foreach ($section in $sslSections) {
    $portMatch  = [regex]::Match($section, 'IP:port\s*:\s*0\.0\.0\.0:(\d+)')
    $hashMatch  = [regex]::Match($section, 'Certificate Hash\s*:\s*([0-9a-fA-F]+)')
    $appIdMatch = [regex]::Match($section, 'Application ID\s*:\s*(\{[0-9a-fA-F\-]+\})')

    if ($portMatch.Success -and $hashMatch.Success -and $appIdMatch.Success) {
        $p = [int]$portMatch.Groups[1].Value
        $portBindings[$p] = @{
            CertHash = $hashMatch.Groups[1].Value
            AppId    = $appIdMatch.Groups[1].Value
        }
    }
}

if (-not $DashboardPort) { $DashboardPort = 8089 }

$dashboardAppId = $null
if ($portBindings.ContainsKey($DashboardPort)) {
    $dashboardAppId = $portBindings[$DashboardPort].AppId
    Write-Host "    Dashboard port $DashboardPort : existing binding found (AppId: $dashboardAppId)" -ForegroundColor Green
} else {
    Write-Host "    Dashboard port $DashboardPort : no existing binding (new)" -ForegroundColor DarkYellow
}

if (-not $dashboardAppId) {
    $dashboardAppId = '{' + [guid]::NewGuid().ToString() + '}'
    Write-Host "    Generated new AppId for Dashboard: $dashboardAppId" -ForegroundColor DarkGray
}

Write-Host ""

Write-Host "  [3/8] DISCOVERING ENTERPRISE CA" -ForegroundColor Cyan

$caConfig = $null

try {
    $caLocator = New-Object -ComObject CertificateAuthority.Config
    $caConfig  = $caLocator.GetConfig(0)
    Write-Host "    [OK] Enterprise CA: $caConfig" -ForegroundColor Green
} catch {
    try {
        $tcaOutput = certutil -TCAInfo 2>&1 | Out-String
        $tcaMatch  = [regex]::Match($tcaOutput, '(?m)^\s*(\S+\\\S+)')
        if ($tcaMatch.Success) {
            $caConfig = $tcaMatch.Groups[1].Value.Trim()
            Write-Host "    [OK] Enterprise CA: $caConfig" -ForegroundColor Green
        } else {
            throw "Parse failed"
        }
    } catch {
        Write-Host "    [WARN] Could not auto-detect Enterprise CA." -ForegroundColor Yellow
        Write-Host '           Format: "CA-SERVER\CA-Name"' -ForegroundColor DarkGray
        Write-Host ""
        $caConfig = Read-Host "    Enter CA config string"
        if ([string]::IsNullOrWhiteSpace($caConfig)) {
            Write-Host "    [FAIL] No CA specified. Exiting." -ForegroundColor Red
            exit 1
        }
    }
}

try {
    $pingResult = certutil -config $caConfig -ping 2>&1 | Out-String
    if ($pingResult -match 'interface is alive') {
        Write-Host "    [OK] CA is reachable" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] CA ping returned unexpected result (may still work)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    [WARN] Could not ping CA (may still work if network allows enrollment)" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "  [4/8] CERTIFICATE DETECTION" -ForegroundColor Cyan

# --- Check for existing valid CA-issued certificate in the local store ---
$existingCert = $null

# Priority 1: cert with our friendly name
$existingCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FriendlyName -like "RTX CA Status Dashboard Cert*" -and
        $_.NotAfter -gt (Get-Date).AddDays(7) -and
        $_.Issuer -ne $_.Subject
    } | Sort-Object NotAfter -Descending | Select-Object -First 1

# Priority 2: any CA-issued cert matching this server's FQDN
if (-not $existingCert) {
    $existingCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Subject -eq "CN=$fqdn" -and
            $_.NotAfter -gt (Get-Date).AddDays(7) -and
            $_.Issuer -ne $_.Subject -and
            $_.Issuer -notmatch 'SMS' -and
            $_.HasPrivateKey
        } | Sort-Object NotAfter -Descending | Select-Object -First 1
}

# Priority 3: cert whose SAN list covers this server's FQDN
if (-not $existingCert) {
    $existingCert = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object {
            $_.NotAfter -gt (Get-Date).AddDays(7) -and
            $_.Issuer -ne $_.Subject -and
            $_.Issuer -notmatch 'SMS' -and
            $_.HasPrivateKey -and
            ($_.DnsNameList | ForEach-Object { $_.Unicode }) -contains $fqdn
        } | Sort-Object NotAfter -Descending | Select-Object -First 1
}

$newCert = $null

if ($existingCert) {
    $daysLeft = [math]::Floor(($existingCert.NotAfter - (Get-Date)).TotalDays)
    Write-Host ""
    Write-Host "    [FOUND] Existing CA-issued certificate in local store:" -ForegroundColor Green
    Write-Host "            Subject    : $($existingCert.Subject)" -ForegroundColor DarkGray
    Write-Host "            Issuer     : $($existingCert.Issuer)" -ForegroundColor DarkGray
    Write-Host "            Thumbprint : $($existingCert.Thumbprint)" -ForegroundColor DarkGray
    Write-Host "            Expires    : $($existingCert.NotAfter.ToString('yyyy-MM-dd')) ($daysLeft days remaining)" -ForegroundColor DarkGray
    $existingSanList = ($existingCert.DnsNameList | ForEach-Object { $_.Unicode }) -join ', '
    if ($existingSanList) {
        Write-Host "            SANs       : $existingSanList" -ForegroundColor DarkGray
    }
    Write-Host ""
    if ($Force) {
        Write-Host "    Re-using existing certificate (-Force specified)." -ForegroundColor Green
        $reuseExisting = 'R'
    } else {
        Write-Host "    [R] Re-use this certificate (recommended)" -ForegroundColor White
        Write-Host "    [N] Request a new certificate from the CA" -ForegroundColor DarkGray
        Write-Host ""
        $reuseExisting = Read-Host "    Re-use existing cert? [R]"
        if ([string]::IsNullOrWhiteSpace($reuseExisting)) { $reuseExisting = 'R' }
    }

    if ($reuseExisting -match '^[Rr]') {
        $newCert = $existingCert
        Write-Host "    [OK] Re-using existing CA certificate" -ForegroundColor Green
        Write-Host "         Subject    : $($newCert.Subject)" -ForegroundColor DarkGray
        Write-Host "         Thumbprint : $($newCert.Thumbprint)" -ForegroundColor DarkGray
        Write-Host "         Expires    : $($newCert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
    }
}


if (-not $newCert) {
	Write-Host "  [5/8] FINDING CERTIFICATE TEMPLATE" -ForegroundColor Cyan
	if (-not $TemplateName -and $Force) {
	    $candidateTemplates = @("WebServer", "DomainWebServer", "Machine")
	    $foundTemplate = $null
	    try {
	        $templateOutput = certutil -CATemplates -config $caConfig 2>&1 | Out-String
	        foreach ($t in $candidateTemplates) {
	            if ($templateOutput -match "(?i)$([regex]::Escape($t))") {
	                $lineMatch = [regex]::Match($templateOutput, "(?im)^\s*($([regex]::Escape($t))[^:]*)")
	                if ($lineMatch.Success) {
	                    $foundTemplate = $lineMatch.Groups[1].Value.Trim()
	                } else {
	                    $foundTemplate = $t
	                }
	                break
	            }
	        }
	    } catch {
	        Write-Host "    [WARN] Could not query CA templates: $($_.Exception.Message)" -ForegroundColor Yellow
	    }
	    if ($foundTemplate) {
	        $TemplateName = $foundTemplate
	        Write-Host "    [OK] Auto-detected template: $TemplateName" -ForegroundColor Green
	    } else {
	        Write-Host "    [FAIL] Could not auto-detect template and -Force was specified. Use -TemplateName." -ForegroundColor Red
	        exit 1
	    }
	} elseif (-not $TemplateName) {
	    $availableTemplates = @()
	    try {
	        Write-Host "    Querying CA for published templates..." -ForegroundColor DarkGray
	        $templateOutput = certutil -CATemplates -config $caConfig 2>&1 | Out-String
	        $lines = $templateOutput -split "`r?`n"
	        foreach ($line in $lines) {
	            $lineMatch = [regex]::Match($line, '^\s*([^:]+):\s*(.+?)(?:\s*--|\s*$)')
	            if ($lineMatch.Success) {
	                $rawName = $lineMatch.Groups[1].Value.Trim()
	                $displayName = $lineMatch.Groups[2].Value.Trim()
	                if ($rawName -and $rawName -notmatch 'certutil') {
	                    $availableTemplates += @{ Name = $rawName; Display = $displayName }
	                }
	            }
	        }
	    } catch {
	        Write-Host "    [WARN] Could not query CA templates: $($_.Exception.Message)" -ForegroundColor Yellow
	    }
	
	    if ($availableTemplates.Count -gt 0) {
	        Write-Host "    [OK] Found $($availableTemplates.Count) published templates." -ForegroundColor Green
	        Write-Host ""
	        for ($i = 0; $i -lt $availableTemplates.Count; $i++) {
	            Write-Host ("      [{0}] {1,-25} ({2})" -f $i, $availableTemplates[$i].Name, $availableTemplates[$i].Display) -ForegroundColor White
	        }
	        Write-Host ""
	        $selection = Read-Host "    Select template by number or type name directly"
	        if ([string]::IsNullOrWhiteSpace($selection)) {
	            Write-Host "    [FAIL] No template specified. Exiting." -ForegroundColor Red
	            exit 1
	        }
	        if ($selection -match '^\d+$' -and [int]$selection -lt $availableTemplates.Count) {
	            $TemplateName = $availableTemplates[[int]$selection].Name
	        } else {
	            $TemplateName = $selection
	        }
	    } else {
	        Write-Host "    [WARN] Could not parse a list of templates from the CA." -ForegroundColor Yellow
	        Write-Host "           Common names: WebServer, DomainWebServer, Machine" -ForegroundColor DarkGray
	        Write-Host ""
	        $TemplateName = Read-Host "    Enter the certificate template name"
	        if ([string]::IsNullOrWhiteSpace($TemplateName)) {
	            Write-Host "    [FAIL] No template specified. Exiting." -ForegroundColor Red
	            exit 1
	        }
	    }
	} else {
	    Write-Host "    Using specified template: $TemplateName" -ForegroundColor Green
	}
	Write-Host ""
	if (-not $Force) {
	    Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkCyan
	    Write-Host "  |  DETECTED CONFIGURATION                                 |" -ForegroundColor DarkCyan
	    Write-Host "  +---------------------------------------------------------+" -ForegroundColor DarkCyan
	    Write-Host "    Server      : $fqdn" -ForegroundColor White
	    Write-Host "    Domain      : $domain" -ForegroundColor White
	    Write-Host "    CA          : $caConfig" -ForegroundColor White
	    Write-Host "    Template    : $TemplateName" -ForegroundColor White
	    Write-Host "    SANs        : $fqdn, $hostName, localhost" -ForegroundColor White
	    Write-Host "    Dashboard   : Port $DashboardPort (AppId: $dashboardAppId)" -ForegroundColor White
	    Write-Host ""
	    $confirm = Read-Host "  Proceed with certificate request? [Y/n]"
	    if ($confirm -match '^[Nn]') {
	        Write-Host "  Cancelled." -ForegroundColor Yellow
	        exit 0
	    }
	    Write-Host ""
	}
} else {
	Write-Host "  [5/8] FINDING CERTIFICATE TEMPLATE" -ForegroundColor Cyan
	Write-Host "    Skipped (re-using existing certificate)." -ForegroundColor DarkGray
	Write-Host ""
}
# --- Request a new certificate only if we don't have one to reuse ---
if (-not $newCert) {
    Write-Host "    Requesting new certificate from Enterprise CA..." -ForegroundColor DarkGray
    Write-Host ""

    $infPath = "$env:TEMP\rtx-ca-dash-setup.inf"
    $csrPath = "$env:TEMP\rtx-ca-dash-setup.csr"
    $cerPath = "$env:TEMP\rtx-ca-dash-setup.cer"
    $rspPath = "$env:TEMP\rtx-ca-dash-setup.rsp"

    Remove-Item $infPath, $csrPath, $cerPath, $rspPath -Force -ErrorAction SilentlyContinue

    $templateOid = $TemplateName -replace '\s', ''

    $inf = @"
[Version]
Signature = "`$Windows NT`$"

[NewRequest]
Subject = "CN=$fqdn"
KeyLength = 2048
KeyAlgorithm = RSA
HashAlgorithm = SHA256
Exportable = TRUE
MachineKeySet = TRUE
RequestType = PKCS10
KeyUsage = 0xa0
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
FriendlyName = "RTX CA Status Dashboard Cert ($hostName)"

[RequestAttributes]
CertificateTemplate = $templateOid

[Extensions]
2.5.29.17 = "{text}"
_continue_ = "dns=$fqdn&"
_continue_ = "dns=$hostName&"
_continue_ = "dns=localhost"
"@

    $inf | Out-File -FilePath $infPath -Encoding ASCII -Force
    Write-Host "    INF file   : $infPath" -ForegroundColor DarkGray

    Write-Host "    Creating certificate request..." -ForegroundColor DarkGray
    $reqResult = certreq -new -q $infPath $csrPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    [FAIL] certreq -new failed:" -ForegroundColor Red
        Write-Host "    $reqResult" -ForegroundColor Red
        exit 1
    }
    Write-Host "    CSR file   : $csrPath" -ForegroundColor DarkGray

    Write-Host "    Submitting to $caConfig..." -ForegroundColor DarkGray
    $submitResult = certreq -submit -q -config $caConfig $csrPath $cerPath 2>&1 | Out-String

    if ($LASTEXITCODE -ne 0) {
        if ($submitResult -match 'pending') {
            Write-Host "" -ForegroundColor Yellow
            Write-Host "    [PENDING] Request requires CA administrator approval." -ForegroundColor Yellow
            Write-Host "    After approval, retrieve with:" -ForegroundColor Yellow
            Write-Host "      certreq -retrieve -config `"$caConfig`" <RequestID> `"$cerPath`"" -ForegroundColor White
            Write-Host "    Then install with:" -ForegroundColor Yellow
            Write-Host "      certreq -accept `"$cerPath`"" -ForegroundColor White
            Write-Host "    Then re-run this script with -Force to bind." -ForegroundColor Yellow
            Write-Host ""
            exit 0
        }
        Write-Host "    [FAIL] certreq -submit failed:" -ForegroundColor Red
        Write-Host "    $submitResult" -ForegroundColor Red
        exit 1
    }

    Write-Host "    Installing certificate..." -ForegroundColor DarkGray
    $acceptResult = certreq -accept -q $cerPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host "    [FAIL] certreq -accept failed:" -ForegroundColor Red
        Write-Host "    $acceptResult" -ForegroundColor Red
        exit 1
    }

    Start-Sleep -Seconds 1
    $newCert = Get-ChildItem Cert:\LocalMachine\My |
        Where-Object {
            $_.FriendlyName -like "RTX CA Status Dashboard Cert*" -and
            $_.NotAfter -gt (Get-Date)
        } | Sort-Object NotAfter -Descending | Select-Object -First 1

    if (-not $newCert) {
        $newCert = Get-ChildItem Cert:\LocalMachine\My |
            Where-Object {
                $_.Subject -eq "CN=$fqdn" -and
                $_.NotAfter -gt (Get-Date) -and
                $_.Issuer -ne $_.Subject
            } | Sort-Object NotBefore -Descending | Select-Object -First 1
    }

    if (-not $newCert) {
        Write-Host "    [FAIL] Could find the installed CA cert." -ForegroundColor Red
        Write-Host "           Check certlm.msc > Personal > Certificates" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "    [OK] Certificate issued and installed" -ForegroundColor Green
    Write-Host "         Subject    : $($newCert.Subject)" -ForegroundColor DarkGray
    Write-Host "         Issuer     : $($newCert.Issuer)" -ForegroundColor DarkGray
    Write-Host "         Thumbprint : $($newCert.Thumbprint)" -ForegroundColor DarkGray
    Write-Host "         Expires    : $($newCert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
    $sanList = ($newCert.DnsNameList | ForEach-Object { $_.Unicode }) -join ', '
    if ($sanList) {
        Write-Host "         SANs       : $sanList" -ForegroundColor DarkGray
    }

    Remove-Item $infPath, $csrPath, $cerPath, $rspPath -Force -ErrorAction SilentlyContinue
}

Write-Host ""

Write-Host "  [6/8] REMOVING OLD SSL BINDINGS" -ForegroundColor Cyan

netsh http delete sslcert ipport=0.0.0.0:$DashboardPort 2>&1 | Out-Null
netsh http delete sslcert ipport="[::]:$DashboardPort" 2>&1 | Out-Null
Write-Host "    [OK] Cleaned bindings on port $DashboardPort" -ForegroundColor DarkGray

Write-Host ""

Write-Host "  [7/8] BINDING CA CERTIFICATE" -ForegroundColor Cyan

$bind4 = netsh http add sslcert ipport=0.0.0.0:$DashboardPort certhash=$($newCert.Thumbprint) appid=$dashboardAppId certstorename=MY 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -or $bind4 -match 'success') {
    Write-Host "    [OK] Dashboard IPv4 bound on port $DashboardPort (AppId: $dashboardAppId)" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Dashboard IPv4 failed on port ${DashboardPort}: $bind4" -ForegroundColor Red
}

$bind6 = netsh http add sslcert ipport="[::]:$DashboardPort" certhash=$($newCert.Thumbprint) appid=$dashboardAppId certstorename=MY 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -or $bind6 -match 'success') {
    Write-Host "    [OK] Dashboard IPv6 bound on port $DashboardPort" -ForegroundColor Green
} else {
    Write-Host "    [WARN] Dashboard IPv6 failed on port $DashboardPort (non-critical)" -ForegroundColor Yellow
}

Write-Host ""

Write-Host "  [8/8] RESTARTING AND VERIFYING" -ForegroundColor Cyan

$webTaskName = "CA-Dashboard-WebServer"
$task = Get-ScheduledTask -TaskName $webTaskName -ErrorAction SilentlyContinue
if ($task) {
    try {
        $task | Stop-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        Start-Sleep -Seconds 1
        $task | Start-ScheduledTask | Out-Null
        Write-Host "    [OK] Restarted: $webTaskName" -ForegroundColor Green
    } catch {
        Write-Host "    [WARN] Could not restart: $webTaskName - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""

Write-Host "  VERIFYING SSL BINDINGS" -ForegroundColor Cyan
$check = netsh http show sslcert ipport=0.0.0.0:$DashboardPort 2>&1 | Out-String
if ($check -match 'Certificate Hash\s*:\s*([0-9a-fA-F]+)') {
    $boundHash = $Matches[1]
    if ($boundHash -eq $newCert.Thumbprint) {
        Write-Host "    [OK] Dashboard (port $DashboardPort) - CA cert verified" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] Dashboard (port $DashboardPort) - Bound hash mismatch: $boundHash" -ForegroundColor Yellow
    }
} else {
    Write-Host "    [FAIL] Dashboard (port $DashboardPort) - No SSL binding found" -ForegroundColor Red
}

Write-Host ""
Write-Host "  +=========================================================+" -ForegroundColor DarkCyan
Write-Host "  |  CA CERTIFICATE DEPLOYED SUCCESSFULLY                    |" -ForegroundColor Green
Write-Host "  +=========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "    Certificate : $($newCert.Subject)" -ForegroundColor White
Write-Host "    Issued by   : $($newCert.Issuer)" -ForegroundColor White
Write-Host "    Thumbprint  : $($newCert.Thumbprint)" -ForegroundColor White
Write-Host "    Expires     : $($newCert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor White
Write-Host ""
Write-Host "    Dashboard URL : https://${fqdn}:${DashboardPort}/" -ForegroundColor Cyan
Write-Host ""
Write-Host "    All domain-joined machines will trust this certificate" -ForegroundColor Green
Write-Host "    automatically (Enterprise CA - no GPO required)." -ForegroundColor Green
Write-Host ""

Write-Output $newCert.Thumbprint
