@echo off
rem bootstrap.bat - Windows bootstrap entry point (Stage 8, Phase F).
rem
rem Thin cmd.exe wrapper over build.ps1 for users who don't invoke PowerShell
rem directly. Builds the compiler and runs the fixed-point self-host check.
rem
rem Usage:   bootstrap.bat [mingw|msvc]
rem   (default toolchain: mingw - fully open source, no Visual Studio needed)

setlocal
set TOOLCHAIN=%1
if "%TOOLCHAIN%"=="" set TOOLCHAIN=mingw

where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
    set PS=pwsh
) else (
    set PS=powershell
)

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" -Toolchain %TOOLCHAIN% -Bootstrap
exit /b %ERRORLEVEL%
