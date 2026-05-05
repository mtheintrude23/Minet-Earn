#!/usr/bin/env pwsh
# Minet Mining Setup - Windows PowerShell Script
$BU = "https://dashboard.minet.vn"
Write-Host ""
Write-Host "===== Minet Mining Setup =====" -ForegroundColor Cyan
Write-Host ""
$EM = Read-Host "Email"
if ([string]::IsNullOrWhiteSpace($EM)) {
    Write-Host "Email required." -ForegroundColor Red
    exit 1
}
Write-Host "Preparing..."

# Kiểm tra curl (không thoát nếu lỗi)
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Installing curl via winget..." -ForegroundColor Yellow
    try {
        winget install --id cURL.cURL -e --silent
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH", "User")
        Write-Host "curl installed." -ForegroundColor Green
    } catch {
        Write-Host "curl install failed, continuing anyway..." -ForegroundColor Yellow
    }
}

function UrlEncode($str) {
    return [System.Uri]::EscapeDataString($str)
}

$EE = UrlEncode $EM
Write-Host "Getting IP..." -ForegroundColor Gray

# Thử nhiều nguồn IP backup
$CI = $null
$ipSources = @(
    "https://api.ipify.org",
    "https://icanhazip.com",
    "https://ifconfig.me/ip",
    "https://api4.my-ip.io/ip"
)

foreach ($src in $ipSources) {
    try {
        $CI = (Invoke-RestMethod -Uri $src -TimeoutSec 10).Trim()
        if (-not [string]::IsNullOrWhiteSpace($CI)) {
            Write-Host "IP: $CI" -ForegroundColor Gray
            break
        }
    } catch {
        Write-Host "Retry IP from $src..." -ForegroundColor Yellow
    }
}

if ([string]::IsNullOrWhiteSpace($CI)) {
    Write-Host "Network error: Cannot get IP." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

$EI = [System.Uri]::EscapeDataString($CI)
$setupUrl = "$BU/api/minecoin/setup?email=$EE&ip=$EI&mode=dashboard"

Write-Host "Fetching setup script..." -ForegroundColor Gray

try {
    $response = Invoke-WebRequest -Uri $setupUrl -UseBasicParsing -TimeoutSec 30
    $scriptContent = $response.Content

    if ([string]::IsNullOrWhiteSpace($scriptContent)) {
        Write-Host "Error: Empty response from server." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }

    Write-Host "Running setup..." -ForegroundColor Green
    Invoke-Expression $scriptContent

} catch {
    Write-Host "Failed to fetch or run setup script: $_" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Read-Host "Press Enter to exit"
