@echo off
setlocal enabledelayedexpansion

:: ============================================================
::  Minet Mining Launcher - Cloudflare Tunnel Edition
:: ============================================================

:: 1. Quyền Admin
net session >nul 2>&1
if errorlevel 1 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "BU=https://dashboard.minet.vn"
set "WD=C:\Minet_Mining"
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

:: 2. Nhập Email
set /p EM="Email: "
if "!EM!"=="" exit /b 1

echo [INFO] Dang lay thong so tu Server Minet...

:: 3. Lấy IP
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set "CI=%%I"
set "EE=!EM:@=%%40!"
set "EE=!EE:+=%%2B!"
set "EI=!CI::=%%3A!"

:: 4. Lấy config từ server
curl -fsSL "!BU!/api/minecoin/setup?email=!EE!&ip=!EI!&mode=dashboard" -o "server_config.txt"
echo [INFO] Da tai xong thong so.
echo ---------------------------------------
type server_config.txt
echo ---------------------------------------

:: 5. Đọc token và port từ server_config.txt
::    (server trả về 2 dòng: TOKEN=xxx và PORT=xxx)
for /f "tokens=1,2 delims==" %%A in (server_config.txt) do (
    if /i "%%A"=="TOKEN" set "CF_TOKEN=%%B"
    if /i "%%A"=="PORT"  set "CF_PORT=%%B"
)

if "!CF_TOKEN!"=="" (
    echo [ERROR] Khong doc duoc TOKEN tu server. Kiem tra lai server_config.txt
    pause
    exit /b 1
)
if "!CF_PORT!"=="" (
    echo [ERROR] Khong doc duoc PORT tu server. Kiem tra lai server_config.txt
    pause
    exit /b 1
)

:: 6. Tải cloudflared nếu chưa có
if not exist "cloudflared.exe" (
    echo [INFO] Dang tai cloudflared...
    curl -L -o cloudflared.exe https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe
    if errorlevel 1 (
        echo [ERROR] Tai cloudflared that bai. Kiem tra ket noi mang.
        pause
        exit /b 1
    )
    echo [INFO] Tai cloudflared thanh cong.
)

:: 7. Chạy tunnel
echo.
echo [INFO] Dang khoi dong Cloudflare Tunnel...
echo [INFO] Token : !CF_TOKEN!
echo [INFO] Port  : !CF_PORT!
echo.

start "Cloudflare Tunnel" cloudflared.exe tunnel --no-autoupdate run --token "!CF_TOKEN!"

echo [DONE] Tunnel da duoc khoi dong trong cua so moi.
echo        Server dang duoc expose qua Cloudflare tai port !CF_PORT!.
pause
