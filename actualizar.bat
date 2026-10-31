@echo off
REM ------------------------------------------------------------
REM Script: actualizar.bat
REM Propósito:
REM   Actualizar Paper y los plugins a la última versión que soporten todos
REM   (ver actualizar.py). Acepta las mismas opciones: --check, --yes, --rollback...
REM ------------------------------------------------------------
cd /d "%~dp0"
chcp 65001 >nul

where python >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: hace falta Python 3 (https://www.python.org/downloads/).' -ForegroundColor Red -ErrorAction SilentlyContinue"
    goto :END
)

python actualizar.py %*

:END
echo.
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
pause >nul
