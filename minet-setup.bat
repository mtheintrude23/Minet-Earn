@echo off
setlocal enabledelayedexpansion

set BU=https://dashboard.minet.vn

echo.
echo ===== Minet Mining Setup =====
echo.

set /p EM=Email: 
if "!EM!"=="" (
    echo Email required.
    exit /b 1
)

echo Preparing...

REM Kiem tra curl co san trong Windows 10/11 khong
where curl >nul 2>&1
if errorlevel 1 (
    echo Installing curl via winget...
    winget install --id cURL.cURL -e --silent
)

REM Lay IP cong khai
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
if "!CI!"=="" (
    echo Network error.
    exit /b 1
)

REM URL-encode email va IP don gian (xu ly @)
set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EE=!EE:%%=%%25!
set EI=!CI::=%%3A!

REM Tai script va chay
curl -fsSL "!BU!/api/minecoin/setup?email=!EE!&ip=!EI!&mode=dashboard" -o "%TEMP%\minet_setup.sh"

REM Chay bang bash neu co (Git Bash / WSL)
where bash >nul 2>&1
if not errorlevel 1 (
    bash "%TEMP%\minet_setup.sh"
) else (
    echo.
    echo [ERROR] Khong tim thay bash.exe
    echo Vui long cai Git for Windows: https://git-scm.com/download/win
    echo Hoac kich hoat WSL: wsl --install
    exit /b 1
)

endlocal
