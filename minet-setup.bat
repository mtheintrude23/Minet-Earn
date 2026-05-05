@echo off
setlocal enabledelayedexpansion
set BU=https://dashboard.minet.vn

:: Kiem tra quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Dang yeu cau quyen Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo ===== Minet Mining Setup (Fixed) =====
echo.
set /p EM=Email: 
if "!EM!"=="" (
    echo [ERROR] Email khong duoc de trong.
    pause
    exit /b 1
)
echo Dang chuan bi...

:: Kiem tra curl
where curl >nul 2>&1
if errorlevel 1 (
    echo [INFO] Dang cai dat curl...
    winget install --id cURL.cURL -e --silent
)

:: Lay IP
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
if "!CI!"=="" (
    echo [ERROR] Loi ket noi mang.
    pause
    exit /b 1
)

:: Encode ky tu dac biet cho URL
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
    echo [ERROR] Khong tim thay Git bash. Vui long cai Git for Windows.
    pause
    exit /b 1
)

:: Tai script setup tu server
curl -fsSL "!SETUP_URL!" -o "%TEMP%\minet_setup.sh"
if not exist "%TEMP%\minet_setup.sh" (
    echo [ERROR] Khong tai duoc script tu server.
    pause
    exit /b 1
)

:: Convert duong dan Windows sang Unix cho Git bash
set UNIX_TEMP=%TEMP:\=/%
set UNIX_TEMP=!UNIX_TEMP:C:=/c!
set UNIX_TEMP=!UNIX_TEMP:c:=/c!

:: Tao thu muc tam thoi va phan quyen cho Git Bash
if not exist "%TEMP%\minet_tmp" mkdir "%TEMP%\minet_tmp"

echo [INFO] Dang chay setup qua Git Bash...

:: FIX QUAN TRONG: Ep Git Bash nhan dien TMPDIR la thu muc User Temp
:: Su dung flag --login de dam bao moi truong bash duoc khoi tao day du
"!BASH_EXE!" --login -c "export TMPDIR='!UNIX_TEMP!/minet_tmp'; export TEMP='!UNIX_TEMP!/minet_tmp'; export TMP='!UNIX_TEMP!/minet_tmp'; bash '!UNIX_TEMP!/minet_setup.sh'"

:done
echo.
echo [DONE] Hoan tat setup!
pause
endlocal
