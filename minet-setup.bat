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

where curl >nul 2>&1
if errorlevel 1 (
    echo Installing curl via winget...
    winget install --id cURL.cURL -e --silent
)

for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set CI=%%I
if "!CI!"=="" (
    echo Network error.
    exit /b 1
)

set EE=!EM:@=%%40!
set EE=!EE:+=%%2B!
set EE=!EE: =%%20!
set EI=!CI::=%%3A!

curl -fsSL "!BU!/api/minecoin/setup?email=!EE!&ip=!EI!&mode=dashboard" -o "%TEMP%\minet_setup.sh"

if not exist "%TEMP%\minet_setup.sh" (
    echo [ERROR] Khong tai duoc script tu server.
    pause
    exit /b 1
)

:: Uu tien Git bash
set BASH_EXE=
for %%P in (
    "C:\Program Files\Git\bin\bash.exe"
    "C:\Program Files (x86)\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
) do (
    if exist %%P (
        set BASH_EXE=%%P
        goto :found_bash
    )
)

:: Thu WSL
wsl -- bash --version >nul 2>&1
if not errorlevel 1 (
    echo [INFO] Dung WSL bash...
    wsl bash "$(wslpath '%TEMP%\minet_setup.sh')"
    goto :done
)

:: Thu where bash lan cuoi
for /f "delims=" %%B in ('where bash 2^>nul') do (
    set BASH_EXE=%%B
    goto :found_bash
)

echo [ERROR] Khong tim thay bash.
echo Cai Git for Windows: https://git-scm.com/download/win
pause
exit /b 1

:found_bash
echo [INFO] Dung bash: !BASH_EXE!
!BASH_EXE! "%TEMP%\minet_setup.sh"

:done
endlocal
