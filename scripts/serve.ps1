$root    = 'C:\RTX-Dashboard-CA-Status'
$port    = 8089
$useHttps = $false

$sslBinding = netsh http show sslcert ipport=0.0.0.0:$port 2>$null
if ($sslBinding -match 'Certificate Hash') {
    $useHttps = $true
}

$listener = New-Object System.Net.HttpListener
$listener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::IntegratedWindowsAuthentication
$protocol = if ($useHttps) { 'https' } else { 'http' }
$listener.Prefixes.Add("${protocol}://+:$port/")

try {
    $listener.Start()
} catch {
    if ($useHttps) {
        Write-Host "HTTPS listener failed: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Falling back to HTTP..." -ForegroundColor Yellow
        $listener.Close()
        $listener = New-Object System.Net.HttpListener
        $listener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::IntegratedWindowsAuthentication
        $protocol = 'http'
        $useHttps = $false
        $listener.Prefixes.Add("http://+:$port/")
        $listener.Start()
    } else {
        throw
    }
}

Write-Host "CA Dashboard server running at ${protocol}://+:$port/"
Write-Host "SSL: $(if ($useHttps) { 'Enabled' } else { 'Disabled (no cert bound to port)' })"
Write-Host "Auth: Windows Integrated (NTLM/Negotiate)"
Write-Host "Press Ctrl+C to stop."

$mimeTypes = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.png'  = 'image/png'
    '.jpg'  = 'image/jpeg'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

function Write-JsonResponse {
    param(
        [Parameter(Mandatory=$true)] $Response,
        [Parameter(Mandatory=$true)] [int]$StatusCode,
        [Parameter(Mandatory=$true)] $Body
    )
    $json  = $Body | ConvertTo-Json -Depth 8
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.StatusCode = $StatusCode
    $Response.ContentType = 'application/json; charset=utf-8'
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    try {
        $identity = $ctx.User.Identity
        $userName = if ($identity -and $identity.IsAuthenticated) { $identity.Name } else { 'ANONYMOUS' }
        $path     = $req.Url.LocalPath

        if ($path -eq '/api/whoami' -and $req.HttpMethod -eq 'GET') {
            $displayName = if ($identity -and $identity.IsAuthenticated) { $identity.Name } else { 'Unknown' }
            Write-JsonResponse -Response $res -StatusCode 200 -Body @{ user = $displayName }
            Write-Host "[$userName] $($req.HttpMethod) $path -> 200 (application/json)"
            continue
        }

        if ($path -eq '/') { $path = '/index.html' }

        $filePath = Join-Path $root $path.TrimStart('/').Replace('/', '\')

        if (Test-Path $filePath -PathType Leaf) {
            $ext         = [System.IO.Path]::GetExtension($filePath).ToLower()
            $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { 'application/octet-stream' }
            $res.ContentType = $contentType
            $res.Headers.Add("Cache-Control", "no-cache, no-store, must-revalidate")
            $res.Headers.Add("Pragma", "no-cache")
            $res.Headers.Add("Expires", "0")
            $res.Headers.Add("Access-Control-Allow-Origin", "*")
            $res.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $res.ContentLength64 = $bytes.Length
            $res.StatusCode = 200
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "[$userName] $($req.HttpMethod) $path -> 200 ($contentType)"
        } else {
            $res.StatusCode = 404
            $body = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $path")
            $res.ContentLength64 = $body.Length
            $res.OutputStream.Write($body, 0, $body.Length)
            Write-Host "[$userName] $($req.HttpMethod) $path -> 404"
        }
    } catch {
        $errorBody = @{ success = $false; message = $_.Exception.Message }
        Write-JsonResponse -Response $res -StatusCode 500 -Body $errorBody
        Write-Host "[$userName] $($req.HttpMethod) $($req.Url.LocalPath) -> 500 (application/json)"
    } finally {
        $res.OutputStream.Close()
    }
}
