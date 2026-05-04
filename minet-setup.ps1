#!/usr/bin/env pwsh
# Minet Mining Setup - Windows PowerShell Script

$BU = "https://dashboard.minet.vn"

Write-Host ""
Write-Host "===== Minet Mining Setup =====" -ForegroundColor Cyan
Write-Host ""

# Nhap email
$EM = Read-Host "Email"
if ([string]::IsNullOrWhiteSpace($EM)) {
    Write-Host "Email required." -ForegroundColor Red
    exit 1
}

Write-Host "Preparing..."

# Kiem tra va cai dat curl neu chua co (dung winget)
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Installing curl via winget..." -ForegroundColor Yellow
    winget install --id cURL.cURL -e --silent
    # Lam moi PATH trong session hien tai
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

# URL-encode email
function UrlEncode($str) {
    $encoded = [System.Uri]::EscapeDataString($str)
    # EscapeDataString da xu ly @, +, % => khop voi sed trong bash
    return $encoded
}

$EE = UrlEncode $EM

# Lay dia chi IP cong khai
try {
    $CI = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
} catch {
    Write-Host "Network error." -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($CI)) {
    Write-Host "Network error." -ForegroundColor Red
    exit 1
}

$EI = [System.Uri]::EscapeDataString($CI)

# Tai ve va chay script setup
$setupUrl = "$BU/api/minecoin/setup?email=$EE&ip=$EI&mode=dashboard"

try {
    $scriptContent = (Invoke-WebRequest -Uri $setupUrl -UseBasicParsing -TimeoutSec 30).Content
    Invoke-Expression $scriptContent
} catch {
    Write-Host "Failed to fetch or run setup script: $_" -ForegroundColor Red
    exit 1
}
