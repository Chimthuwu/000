@echo off
REM Terraria 3D - Git repository preflight.
REM Confirms this folder is the canonical Terraria 3D repository before any
REM staging, commit or push. Exits 1 on the first mismatch.
setlocal
set "EXPECTED_REMOTE=https://github.com/Chimthuwu/000.git"
set "EXPECTED_BRANCH=main"

cd /d "%~dp0"
echo Terraria 3D Git preflight
echo   directory : %CD%

set "ROOT="
for /f "delims=" %%i in ('git rev-parse --show-toplevel 2^>nul') do set "ROOT=%%i"
if not defined ROOT (
  echo   RESULT    : FAIL - this folder is not inside a Git repository
  exit /b 1
)
echo   git root  : %ROOT%

set "PREFIX="
for /f "delims=" %%i in ('git rev-parse --show-prefix 2^>nul') do set "PREFIX=%%i"
if defined PREFIX (
  echo   RESULT    : FAIL - run this from the repository root, not a subfolder
  exit /b 1
)

set "BRANCH="
for /f "delims=" %%i in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%i"
set "HEAD="
for /f "delims=" %%i in ('git rev-parse HEAD 2^>nul') do set "HEAD=%%i"
set "REMOTE="
for /f "delims=" %%i in ('git config --get remote.origin.url 2^>nul') do set "REMOTE=%%i"
echo   branch    : %BRANCH%
echo   head      : %HEAD%
echo   remote    : %REMOTE%

if not "%REMOTE%"=="%EXPECTED_REMOTE%" (
  echo   RESULT    : FAIL - remote is not %EXPECTED_REMOTE%
  exit /b 1
)
if not "%BRANCH%"=="%EXPECTED_BRANCH%" (
  echo   RESULT    : FAIL - branch is not %EXPECTED_BRANCH%
  exit /b 1
)
findstr /c:"Terraria 3D" project.godot >nul 2>nul
if errorlevel 1 (
  echo   RESULT    : FAIL - project.godot does not declare the Terraria 3D identity
  exit /b 1
)
if not exist "scripts\world\terrain_atlas.gd" (
  echo   RESULT    : FAIL - this tree is not the canonical Terraria 3D project
  exit /b 1
)

echo   RESULT    : PASS - canonical Terraria 3D repository
exit /b 0
