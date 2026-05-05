@echo off
setlocal enabledelayedexpansion
set BU=https://dashboard.minet.vn

:: Kiem tra quyen Admin
net session >nul 2>&1
if errorlevel 1 (
    echo [INFO] Can quyen Administrator. Dang yeu cau cap quyen...
    powershell -Command "Start-Process cmd -ArgumentList '/c, \"%~f0\"' -Verb RunAs"
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

curl -fsSL "!BU!/api/minecoin/setup?email=!EE!&ip=!EI!&mode=dashboard" -o "%TEMP%\minet_setup.sh"

if not exist "%TEMP%\minet_setup.sh" (
    echo [ERROR] Khong tai duoc script tu server.
    pause
    exit /b 1
)

:: Uu tien WSL
wsl -- bash --version >nul 2>&1
if not errorlevel 1 (
    echo [INFO] Dung WSL bash...
    for /f "delims=" %%W in ('wsl wslpath "%TEMP%\minet_setup.sh"') do set WSL_PATH=%%W
    wsl bash "!WSL_PATH!"
    goto :done
)

:: Fallback Git bash
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

echo [ERROR] Khong tim thay bash.
pause
exit /b 1

:found_bash
echo [INFO] Dung Git bash...
!BASH_EXE! "%TEMP%\minet_setup.sh"

:done
echo.
echo [DONE] Hoan tat!
pause
endlocal
