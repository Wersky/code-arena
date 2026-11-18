@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion
rem ============================================================
rem  代码擂台 Code Arena - Web 一键打包（免 R2 / 免绑卡）
rem
rem  做什么：
rem    1. 剥离 llm_config.gd 里的内置 key（否则会被编进 pck，浏览器可扒）
rem    2. 导出 Web 版
rem    3. 还原源码
rem    4. 校验 pck 无凭据残留（解 zstd 真扫）
rem    5. 把 pck / wasm 切成 <25 MiB 的分片（Workers 单文件上限）
rem    6. 整理出 worker\public 部署目录
rem
rem  用法：双击本文件，或 tools\export_web.bat
rem  然后：cd worker && wrangler deploy
rem ============================================================

set "PROJ=%~dp0.."
set "GODOT=D:\zcode-work\godot\engine\Godot_v4.7.2-stable_win64_console.exe"
set "OUT=%PROJ%\build\web"
set "CFG=%PROJ%\scripts\llm\llm_config.gd"
set "BAK=%CFG%.webexport-bak"
set "PY=python"

if not exist "%GODOT%" (
  echo [ERROR] Godot engine not found: %GODOT%
  pause & exit /b 1
)
if not exist "%CFG%" (
  echo [ERROR] llm_config.gd not found: %CFG%
  pause & exit /b 1
)
if exist "%BAK%" (
  echo [ERROR] leftover backup: %BAK%
  echo         Restore first:  copy /y "%BAK%" "%CFG%"
  pause & exit /b 1
)

echo [1/7] back up llm_config.gd ...
copy /y "%CFG%" "%BAK%" >nul
if errorlevel 1 (
  echo [ERROR] backup failed
  pause & exit /b 1
)

echo [2/7] strip builtin credentials ...
%PY% "%PROJ%\tools\strip_builtin_keys.py" strip "%CFG%"
if errorlevel 1 goto :restore_fail
%PY% "%PROJ%\tools\strip_builtin_keys.py" check "%CFG%"
if errorlevel 1 goto :restore_fail

echo [3/7] import + export web ...
"%GODOT%" --headless --path "%PROJ%" --import >nul 2>&1
if not exist "%OUT%" mkdir "%OUT%"
"%GODOT%" --headless --path "%PROJ%" --export-release "Web" "%OUT%\game.html"
set "RC=%ERRORLEVEL%"

echo [4/7] restore llm_config.gd ...
copy /y "%BAK%" "%CFG%" >nul
if errorlevel 1 (
  echo [WARN] RESTORE FAILED - fix manually:
  echo        copy /y "%BAK%" "%CFG%"
) else (
  del /q "%BAK%"
  echo        restored
)

if not "%RC%"=="0" (
  echo [ERROR] export failed ^(exit %RC%^)
  pause & exit /b 1
)

echo [5/7] verify pck has no credentials ...
%PY% "%PROJ%\tools\verify_web_pack.py" "%OUT%\game.pck"
if errorlevel 1 (
  echo.
  echo [ERROR] pck still contains credentials - DO NOT DEPLOY
  pause & exit /b 1
)

echo [6/7] split oversized files ^(<25 MiB per file^) ...
%PY% "%PROJ%\tools\split_pck.py" "%OUT%" --target game.pck >nul
if errorlevel 1 (
  echo [ERROR] split game.pck failed
  pause & exit /b 1
)
%PY% "%PROJ%\tools\split_pck.py" "%OUT%" --target game.wasm >nul
if errorlevel 1 (
  echo [ERROR] split game.wasm failed
  pause & exit /b 1
)

echo [7/7] stage deploy directory ...
%PY% "%PROJ%\tools\stage_web.py"
if errorlevel 1 (
  echo [ERROR] staging failed
  pause & exit /b 1
)

echo 部署目录：worker\public\
echo.
echo 下一步：
echo   cd worker
echo   wrangler deploy
echo.
pause
exit /b 0

:restore_fail
echo [FAIL] restoring llm_config.gd ...
copy /y "%BAK%" "%CFG%" >nul && del /q "%BAK%"
pause & exit /b 1
