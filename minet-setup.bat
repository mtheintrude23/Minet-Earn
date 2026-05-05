@echo off
setlocal enabledelayedexpansion

:: 1. Quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: 2. Thu muc lam viec
set "WD=C:\Minet_Fast"
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

echo =========================================
echo    MINET SETUP - FINAL STABLE FIX
echo =========================================

:: 3. Nhap Email
set /p EM="Nhap Email: "
if "!EM!"=="" exit

:: 4. Tai file va "Mo khoa" ngay lap tuc
echo [1/3] Dang tai file va xac minh...
powershell -Command "^
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; ^
    Invoke-WebRequest -Uri 'https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip' -OutFile 'c.zip'; ^
    Unblock-File -Path 'c.zip'; ^
"

:: 5. Giai nen bang cach goi truc tiep Shell.Application (Cach nay rat kho bi vang)
echo [2/3] Dang giai nen bang Engine moi...
powershell -Command "^
    $shell = New-Object -ComObject Shell.Application; ^
    $zip = $shell.NameSpace((Get-Item 'c.zip').FullName); ^
    $dest = $shell.NameSpace((Get-Item '.').FullName); ^
    $dest.CopyHere($zip.Items(), 0x10); ^
"

:: 6. Don dep va cau hinh
echo [3/3] Thiet lap cau hinh...
move /y frp_*\frpc.exe minet.exe >nul 2>&1
rd /s /q frp_0.51.3_windows_amd64 >nul 2>&1
del /f /q c.zip >nul 2>&1

echo [common]> config.ini
echo server_addr = dashboard.minet.vn>> config.ini
echo server_port = 7000>> config.ini
echo token = minet2024>> config.ini
echo.>> config.ini
echo [mine-%EM%]>> config.ini
echo type = tcp>> config.ini
echo local_ip = 127.0.0.1>> config.ini
echo local_port = 3333>> config.ini
echo remote_port = 0>> config.ini

echo -----------------------------------------
echo [OK] Neu thay file minet.exe xuat hien la thanh cong!
echo Dang chay Miner...
start minet.exe -c config.ini
pause
