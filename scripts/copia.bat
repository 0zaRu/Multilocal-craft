@echo off
REM Lanza scripts/copia.sh con el bash de Git para Windows. Toda la lógica está en el .sh.
setlocal
chcp 65001 >nul
set "BASH_EXE="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE for /f "delims=" %%g in ('where git 2^>nul') do if not defined BASH_EXE if exist "%%~dpg..\bin\bash.exe" set "BASH_EXE=%%~dpg..\bin\bash.exe"
if not defined BASH_EXE (
    echo ERROR: hace falta Git para Windows. Instalalo con: winget install -e --id Git.Git
    pause
    exit /b 1
)
set "SCRIPT=%~dp0copia.sh"
set "SCRIPT=%SCRIPT:\=/%"
"%BASH_EXE%" "%SCRIPT%" %*
set CODE=%ERRORLEVEL%
echo.
pause
exit /b %CODE%
