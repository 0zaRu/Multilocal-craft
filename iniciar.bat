@echo off
setlocal enabledelayedexpansion

REM ------------------------------------------------------------
REM Script: iniciar.bat
REM Propósito:
REM   Arrancar el servidor de Minecraft en modo local (Java).
REM   Permite decidir si se sincroniza el mundo desde GitHub.
REM ------------------------------------------------------------

:: --- Cambiar al directorio donde esta el script ---
cd /d "%~dp0"

:: --- Configuración ---
set MEMORIA_XMX=6
if not "%~1"=="" set MEMORIA_XMX=%~1

:: --- Mensaje de inicio y verificación de privilegios ---
powershell -Command "Write-Host '--- Asistente para iniciar el Servidor de Minecraft (modo local) ---' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Necesitas permisos de administrador para continuar.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''iniciar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    goto :END
)

:: --- Preguntar si se debe sincronizar desde GitHub ---
echo.
powershell -Command "Write-Host '¿Quieres actualizar el mundo desde GitHub?' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'ADVERTENCIA: Esto sobrescribira cualquier cambio local que no hayas subido.' -ForegroundColor Red -ErrorAction SilentlyContinue"
set ACTUALIZAR_GIT=N
set /p ACTUALIZAR_GIT="Responde S para actualizar o Enter para continuar con los datos locales: "

if /i "%ACTUALIZAR_GIT%"=="S" (
    powershell -Command "Write-Host 'Actualizando desde GitHub...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    
    git fetch origin main >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: No se pudo conectar a GitHub. Se continuara con los datos locales.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    ) else (
        git reset --hard origin/main >nul 2>&1
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ERROR: Hubo un problema al aplicar las actualizaciones. Se continuara con los datos locales.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        ) else (
            powershell -Command "Write-Host 'Mundo actualizado correctamente desde GitHub.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        )
    )
) else (
    powershell -Command "Write-Host 'Se utilizaran los datos locales sin sincronizar desde GitHub.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
)

:: --- Preguntar memoria si no se pasó como argumento ---
if "%~1"=="" (
    echo.
    powershell -Command "Write-Host 'Memoria RAM para el servidor (Xmx):' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    set /p MEMORIA_INPUT="Ingresa la cantidad en GB (por defecto 6, presiona Enter para mantener): "
    if not "!MEMORIA_INPUT!"=="" set MEMORIA_XMX=!MEMORIA_INPUT!
)

powershell -Command "Write-Host 'Configurando servidor con Xmx%MEMORIA_XMX%G de RAM...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"

:: --- Verificar archivo JAR ---
if not exist "server 2025\paper-1.21.10.jar" (
    if not exist "server 2025\paper-1.21.9.jar" (
        powershell -Command "Write-Host 'ERROR: No se encuentra el archivo del servidor (paper-1.21.10.jar)' -ForegroundColor Red -ErrorAction SilentlyContinue"
        goto :END
    ) else (
        set JAR_FILE=paper-1.21.9.jar
    )
) else (
    set JAR_FILE=paper-1.21.10.jar
)

:: --- Lanzar servidor ---
echo.
powershell -Command "Write-Host 'Iniciando servidor de Minecraft con %JAR_FILE%...' -ForegroundColor Green -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'IMPORTANTE: Mantén esta ventana abierta mientras el servidor esté funcionando.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'Para detener el servidor, escribe ''stop'' en la consola.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
echo.
cd "server 2025"
java -Xms1G -Xmx%MEMORIA_XMX%G -jar %JAR_FILE% nogui
cd ..

:END
echo.
powershell -Command "Write-Host 'Servidor detenido.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
pause >nul
endlocal