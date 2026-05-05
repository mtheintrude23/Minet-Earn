@echo off
setlocal enabledelayedexpansion
set BU=https://dashboard.minet.vn

:: Kiem tra quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Can quyen Administrator. Dang yeu cau cap quyen...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

echo.
echo ===== Minet Mining Setup =====
echo.
set /p EM=Email: 
if "!EM!"=="" (
    echo Email required.
    pause
    exit /b 1
)
echo Preparing...

where curl >nul 2>&1
if errorlevel 1 (
    echo Installing curl via winget...
    winget install --id cURL.cURL -e --silent
)

for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
if "!CI!"=="" (
    echo [ERROR] Network error.
    pause
    exit /b 1
)

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
    echo Vui long cai Git for Windows: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo [INFO] Dung bash: !BASH_EXE!

:: Tai script
curl -fsSL "!SETUP_URL!" -o "%TEMP%\minet_setup.sh"
if not exist "%TEMP%\minet_setup.sh" (
    echo [ERROR] Khong tai duoc script.
    pause
    exit /b 1
)

:: Convert duong dan Windows -> Unix cho Git bash
set UNIX_TEMP=%TEMP:\=/%
set UNIX_TEMP=!UNIX_TEMP:C:=/c!

:: Tao thu muc tmp rieng co quyen ghi
mkdir "%TEMP%\minet_tmp" 2>nul

:: Chay bash voi TMPDIR tro ve thu muc user co quyen ghi
"!BASH_EXE!" -c "export TMPDIR='!UNIX_TEMP!/minet_tmp'; export TEMP='!UNIX_TEMP!/minet_tmp'; export TMP='!UNIX_TEMP!/minet_tmp'; bash '!UNIX_TEMP!/minet_setup.sh'"

:done
echo.
echo [DONE] Hoan tat!
pause
endlocal
