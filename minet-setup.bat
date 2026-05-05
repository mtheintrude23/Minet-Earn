@echo off
setlocal enabledelayedexpansion
set BU=https://dashboard.minet.vn

:: 1. Kiem tra quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Dang yeu cau quyen Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: 2. Tao thu muc lam viec trong o C de thoat khoi moi rac roi phan quyen
set WORK_DIR=C:\Minet_Mining
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

echo.
echo ===== Minet Mining Setup (Native PowerShell) =====
echo.
set /p EM=Email: 
if "!EM!"=="" (echo [ERROR] Email required. & pause & exit /b 1)

:: Lay IP
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EE=!EE: =%%20!
set EI=!CI::=%%3A!

set SETUP_URL=!BU!/api/minecoin/setup?email=!EE!^&ip=!EI!^&mode=dashboard

echo [INFO] Dang tai script va thiet lap moi truong...

:: 3. Thay vi dung Bash, ta dung PowerShell de tai va thuc thi
:: Buoc nay se tai file .sh ve nhung chung ta se trich xuat cac lenh ben trong
curl -fsSL "!SETUP_URL!" -o "minet_setup.sh"

echo [INFO] Dang giai nen va cai dat tunnel qua PowerShell...

:: 4. Chay PowerShell de gia lap cac buoc trong script .sh
:: Chung ta dung lenh Expand-Archive cua PowerShell de thay the cho 'tar' cua Linux
powershell -Command ^
    "$email = '!EM!'; ^
    $workDir = 'C:\Minet_Mining'; ^
    cd $workDir; ^
    Write-Host '[1/3] Dang tai goi cai dat...'; ^
    Invoke-WebRequest -Uri 'https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip' -OutFile 'frp.zip'; ^
    Write-Host '[2/3] Dang giai nen...'; ^
    Expand-Archive -Path 'frp.zip' -DestinationPath '.\temp' -Force; ^
    Move-Item -Path '.\temp\*\frpc.exe' -Destination '.\frpc.exe' -Force; ^
    Remove-Item -Path 'frp.zip', '.\temp' -Recurse -Force; ^
    Write-Host '[3/3] Dang cau hinh...'; ^
    $config = '[common]`nserver_addr = dashboard.minet.vn`nserver_port = 7000`ntoken = minet2024`n`n[mine-!EM!]`ntype = tcp`nlocal_ip = 127.0.0.1`nlocal_port = 3333`nremote_port = 0'; ^
    $config | Out-File -FilePath 'frpc.ini' -Encoding ascii;"

echo.
echo [DONE] Da thiet lap xong bang cong cu mac dinh cua Windows!
echo [INFO] De bat dau dao, hay chay file frpc.exe trong C:\Minet_Mining
pause
endlocal
