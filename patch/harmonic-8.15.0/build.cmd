@echo off
rem Wrapper so build.ps1 can be started from cmd.exe / Explorer.
rem   build.cmd gnu
rem   build.cmd msvc -Stages build,dist
if "%~1"=="" (
  echo usage: %~nx0 gnu^|msvc [build.ps1 options]
  exit /b 1
)
set "TC=%~1"
shift
set "REST="
:collect
if "%~1"=="" goto run
set "REST=%REST% %1"
shift
goto collect
:run
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Toolchain %TC% %REST%
exit /b %ERRORLEVEL%
