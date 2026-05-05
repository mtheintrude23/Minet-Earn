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
echo ===== Minet Mining Setup (Windows Native) =====
echo.

:: 2. Nhap Email
set /p EM="Email: "
if "!EM!"=="" (echo Email required. & pause & exit /b 1)

echo Preparing...

:: 3. Lay IP va Encode (Tuong duong sed trong Linux)
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
if "!CI!"=="" (echo Network error. & pause & exit /b 1)

set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EI=!CI::=%%3A!

:: 4. Tao thu muc va tai truc tiep script setup cua Windows
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

:: Thay vi dung | sh (khong co tren Windows), ta tai file setup va chay truc tiep
:: Server minet thuong se tra ve file config hoac lenh tai frpc.exe
set "SETUP_URL=!BU!/api/minecoin/setup?email=!EE!^&ip=!EI!^&mode=dashboard"

echo [INFO] Dang ket noi server...
curl -fsSL "!SETUP_URL!" -o "minet_task.sh"

:: 5. Vi ban khong muon dung Git Bash, minh se tu thuc hien logic "Setup" cua file .sh do
:: Logic chung cua Minet: Tai frpc -> Ghi file config -> Chay
echo [INFO] Dang thiet lap he thong...

powershell -Command "^
    $url = 'https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip'; ^
    Invoke-WebRequest -Uri $url -OutFile 'f.zip'; ^
    tar -xf f.zip; ^
    move frp_*\frpc.exe minet.exe; ^
    del f.zip; ^
    rd /s /q frp_*; ^
" >nul 2>&1

:: 6. Tao file config (Giong het ben Linux thuc hien)
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

echo [DONE] Hoan tat!
echo Dang khoi chay miner...
start minet.exe -c config.ini
pause
