#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$HostName,
    [string]$Domain,
    [switch]$Force,
    [switch]$SkipBinding,
    [int]$HttpsPort
)
$ErrorActionPreference = 'Stop'
if (-not $HostName) { $HostName = $env:COMPUTERNAME }
if (-not $Domain) { $Domain = (Get-WmiObject Win32_ComputerSystem).Domain }
$FQDN = "${HostName}.${Domain}"

Write-Host ""
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host "  |   RTX CA Status Dashboard -- SSL Certificate Setup     | " -ForegroundColor DarkCyan
Write-Host "  +========================================================+" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Hostname : $HostName" -ForegroundColor DarkGray
Write-Host "  FQDN     : $FQDN" -ForegroundColor DarkGray
Write-Host "  SAN      : $FQDN, $HostName, localhost" -ForegroundColor DarkGray
Write-Host ""

if (-not $Force) {
    $confirm = Read-Host "  Create dashboard SSL certificate? [Y/n]"
    if ($confirm -match '^[Nn]') {
        Write-Host "  Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""
Write-Host "  [1/4] CLEANING OLD CERTIFICATES" -ForegroundColor Cyan

$oldCerts = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
Where-Object { $_.FriendlyName -like "RTX CA Status Dashboard*" }

$boundHashes = @()
$sslDump = netsh http show sslcert 2>&1 | Out-String
$sslDump -split '(?=IP:port\s*:)' | ForEach-Object {
    if ($_ -match 'Certificate Hash\s*:\s*([0-9a-fA-F]+)') { $boundHashes += $Matches[1] }
}

foreach ($old in $oldCerts) {
    if ($old.Thumbprint -in $boundHashes) {
        Write-Host "    [SKIP] Cert bound to another port: $($old.Thumbprint.Substring(0,8))... ($($old.Subject))" -ForegroundColor DarkYellow
        continue
    }
    Write-Host "    Removing from Personal: $($old.Thumbprint.Substring(0,8))... ($($old.Subject))" -ForegroundColor DarkYellow
    Remove-Item "Cert:\LocalMachine\My\$($old.Thumbprint)" -Force -ErrorAction SilentlyContinue
}

$oldRoot = Get-ChildItem Cert:\LocalMachine\Root -ErrorAction SilentlyContinue |
Where-Object { $_.FriendlyName -like "RTX CA Status Dashboard*" }

foreach ($old in $oldRoot) {
    if ($old.Thumbprint -in $boundHashes) {
        Write-Host "    [SKIP] Cert bound to another port: $($old.Thumbprint.Substring(0,8))..." -ForegroundColor DarkYellow
        continue
    }
    Write-Host "    Removing from Root: $($old.Thumbprint.Substring(0,8))..." -ForegroundColor DarkYellow
    Remove-Item "Cert:\LocalMachine\Root\$($old.Thumbprint)" -Force -ErrorAction SilentlyContinue
}

if (-not $oldCerts -and -not $oldRoot) {
    Write-Host "    [OK] No old certificates found" -ForegroundColor Green
}

Write-Host ""
Write-Host "  [2/4] CREATING CERTIFICATE" -ForegroundColor Cyan

$cert = $null
$existingValid = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
    Where-Object {
        $_.FriendlyName -like "RTX CA Status Dashboard*" -and
        $_.NotAfter -gt (Get-Date) -and
        ($_.DnsNameList.Unicode -contains $FQDN -or $_.Subject -eq "CN=$FQDN")
    } | Sort-Object NotAfter -Descending | Select-Object -First 1

if ($existingValid) {
    Write-Host "    [OK] Reusing existing valid certificate" -ForegroundColor Green
    Write-Host "         Thumbprint : $($existingValid.Thumbprint)" -ForegroundColor DarkGray
    Write-Host "         Expires    : $($existingValid.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
    $cert = $existingValid
}
else {
    $certParams = @{
        DnsName           = @($FQDN, $HostName, "localhost")
        CertStoreLocation = "Cert:\LocalMachine\My"
        FriendlyName      = "RTX CA Status Dashboard ($HostName)"
        NotAfter          = (Get-Date).AddYears(5)
        KeyLength         = 2048
        KeyAlgorithm      = "RSA"
        HashAlgorithm     = "SHA256"
        KeyUsage          = @("DigitalSignature", "KeyEncipherment")
        TextExtension     = @(
            "2.5.29.37={text}1.3.6.1.5.5.7.3.1"
        )
        Provider          = "Microsoft RSA SChannel Cryptographic Provider"
        KeySpec           = "KeyExchange"
    }
    $cert = New-SelfSignedCertificate @certParams
    try {
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
        if ($rsa -and $rsa.CspKeyContainerInfo) {
            $keyName = $rsa.CspKeyContainerInfo.UniqueKeyContainerName
            $keyPath = "$env:ALLUSERSPROFILE\Microsoft\Crypto\RSA\MachineKeys\$keyName"
            if (Test-Path $keyPath) {
                icacls $keyPath /grant "Everyone:RX" /Q | Out-Null
            }
        }
    } catch {
        Write-Host "    [WARN] Could not update private key ACLs." -ForegroundColor Yellow
    }
    Write-Host "    [OK] Certificate created" -ForegroundColor Green
    Write-Host "         Subject    : CN=$FQDN" -ForegroundColor DarkGray
    Write-Host "         Thumbprint : $($cert.Thumbprint)" -ForegroundColor DarkGray
    Write-Host "         Expires    : $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "  [3/4] ADDING TO TRUSTED ROOT" -ForegroundColor Cyan
try {
    $rootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
    $rootStore.Open("ReadWrite")
    $rootStore.Add($cert)
    $rootStore.Close()
    Write-Host "    [OK] Certificate added to Trusted Root CAs" -ForegroundColor Green
    Write-Host "         Chrome will trust this certificate locally." -ForegroundColor DarkGray
}
catch {
    Write-Host "    [WARN] Could not add to Root store: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host ""
if ($SkipBinding -or -not $HttpsPort) {
    Write-Host "  [4/4] HTTPS BINDING (SKIPPED)" -ForegroundColor DarkGray
    $bound = $true
}
else {
    Write-Host "  [4/4] BINDING TO DASHBOARD PORT $HttpsPort" -ForegroundColor Cyan
    $bound = $false
    try {
        netsh http delete sslcert ipport=0.0.0.0:$HttpsPort 2>$null | Out-Null
        $appId = '{4dc3e181-e14b-4a21-b022-59fc669b0934}'
        $result = netsh http add sslcert ipport=0.0.0.0:$HttpsPort certhash=$($cert.Thumbprint) appid=$appId certstorename=My
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    [OK] Certificate bound via HTTP.SYS on port $HttpsPort" -ForegroundColor Green
            $bound = $true
        }
        else { throw "netsh returned: $result" }
    }
    catch {
        Write-Host "    [FAIL] Could not bind certificate to port ${HttpsPort}: $($_.Exception.Message)" -ForegroundColor Red
    }
    if ($bound) {
        $sslCheck = netsh http show sslcert ipport=0.0.0.0:$HttpsPort 2>$null
        if ($sslCheck -match 'Certificate Hash') {
            Write-Host "    [OK] SSL binding verified on 0.0.0.0:$HttpsPort" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "  +--------------------------------------------------------+" -ForegroundColor DarkCyan
if ($bound) {
    Write-Host "  |  SSL CONFIGURED SUCCESSFULLY                           |" -ForegroundColor Green
    Write-Host "  |  Dashboard should be accessible via HTTPS              |" -ForegroundColor DarkGray
}
else {
    Write-Host "  |  SSL CONFIGURATION FAILED                              |" -ForegroundColor Red
}
Write-Host "  +--------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""
Write-Output $cert.Thumbprint
