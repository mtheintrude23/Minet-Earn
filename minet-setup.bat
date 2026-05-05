@echo off
setlocal enabledelayedexpansion

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

:: 4. Tải file setup gốc của server về (Thay vì chạy thẳng, ta lưu lại để xem)
curl -fsSL "!BU!/api/minecoin/setup?email=!EE!&ip=!EI!&mode=dashboard" -o "server_script.txt"

echo [INFO] Da tai xong thong so.
echo ---------------------------------------
:: Hien thi noi dung server tra ve de ban kiem tra xem co dung config ko
type server_script.txt
echo ---------------------------------------

:: 5. Tai frpc neu chua co
if not exist "frpc.exe" (
    echo [INFO] Dang tai frpc...
    curl -L -o f.zip https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip
    tar -xf f.zip
    for /r %%i in (frpc.exe) do copy /y "%%i" "frpc.exe" >nul
    del f.zip
)

echo.
echo [DONE] Bay gio ban hay copy cai doan config trong 'server_script.txt' vao file 'frpc.ini' roi chay nhe.
pause
