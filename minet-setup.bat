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

echo.
echo ===== Minet Mining Setup (Windows CMD) =====
echo.

:: 2. Nhập Email
set /p EM="Email: "
if "!EM!"=="" (echo Email required. & pause & exit /b 1)

echo Preparing...

:: 3. Lấy IP và Encode Email/IP (Thay cho sed)
for /f "delims=" %%I in ('curl -sf https://api.ipify.org') do set "CI=%%I"
if "!CI!"=="" (echo Network error. & pause & exit /b 1)

set "EE=!EM:@=%%40!"
set "EE=!EE:+=%%2B!"
set "EI=!CI::=%%3A!"

:: 4. Tạo thư mục làm việc
if not exist "%WD%" mkdir "%WD%"
cd /d "%WD%"

:: 5. Tải bản frp cho Windows (Đúng chuẩn thay vì chạy | sh của Linux)
echo [1/2] Downloading tunnel...
curl -L -o frp.zip https://github.com/fatedier/frp/releases/download/v0.51.3/frp_0.51.3_windows_amd64.zip

:: 6. Giải nén và chạy ngay tại chỗ (Không đổi tên, không minet.exe gì hết)
echo [2/2] Extracting...
tar -xf frp.zip
del /f /q frp.zip

:: Nhảy vào thư mục vừa giải nén
for /d %%d in (frp_*) do cd /d "%%d"

:: 7. Tạo config đúng chuẩn
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
) > frpc.ini

echo.
echo [DONE] Hoan tat! Dang khoi chay frpc...
echo ---------------------------------------
timeout /t 2 >nul

:: Chạy đúng file frpc.exe của nó
start frpc.exe -c frpc.ini

echo [INFO] Neu thay bang den frpc hien len la thanh cong.
pause
