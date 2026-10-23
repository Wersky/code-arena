@echo off
chcp 65001 >nul
setlocal
rem ============================================================
rem  代码擂台 Code Arena - Windows 打包脚本
rem  用法：双击本文件，或  tools\export_win.bat
rem  产物：D:\zcode-work\godot\dist\code-arena\code-arena.exe
rem ============================================================

set "PROJ=%~dp0.."
set "GODOT=D:\zcode-work\godot\engine\Godot_v4.7.2-stable_win64_console.exe"
set "OUT=D:\zcode-work\godot\dist\code-arena"

if not exist "%GODOT%" (
  echo [ERROR] Godot engine not found: %GODOT%
  pause & exit /b 1
)

echo [1/3] import assets ...
"%GODOT%" --headless --path "%PROJ%" --import >nul 2>&1

echo [2/3] export release ...
"%GODOT%" --headless --path "%PROJ%" --export-release "Windows Desktop" "%OUT%\code-arena.exe"
if errorlevel 1 (
  echo [ERROR] export failed
  pause & exit /b 1
)

echo [3/3] done.
echo.
echo   %OUT%\code-arena.exe
echo.
pause
