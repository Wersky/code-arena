@echo off
rem ============================================================
rem  link_skills.bat - rebuild .github/skills junction
rem  Why: CodeArts Agent auto-discovers skills from .github/skills,
rem       while the canonical library lives in .zcode/skills
rem       (tracked in git, shared by every agent).
rem  Run this once after cloning the repo on a new machine.
rem ============================================================
setlocal
set "ROOT=%~dp0.."
set "LINK=%ROOT%\.github\skills"
set "TARGET=%ROOT%\.zcode\skills"

if not exist "%TARGET%" (
  echo [ERROR] skill library not found: %TARGET%
  pause & exit /b 1
)

if exist "%LINK%" (
  echo [SKIP] %LINK% already exists
  exit /b 0
)

if not exist "%ROOT%\.github" mkdir "%ROOT%\.github"
cmd /c mklink /J "%LINK%" "%TARGET%"
if errorlevel 1 (
  echo [ERROR] mklink failed - try running as administrator
  pause & exit /b 1
)
echo [OK] linked: %LINK% -^> %TARGET%
