@echo off
setlocal

:: --- Forzar ejecución en la carpeta del script ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
powershell -Command "Write-Host 'Iniciando script de despliegue de servidor ZeroTier...' -ForegroundColor Green"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Por favor, haga clic derecho en el archivo .bat y seleccione ''Ejecutar como administrador''.' -ForegroundColor Red"
    pause
    exit /b 1
)

:: --- Verificar si la IP flotante está en uso ---
powershell -Command "Write-Host 'Verificando si la IP flotante %IPFLOTANTE% ya está en uso...' -ForegroundColor Yellow"
ping -n 1 %IPFLOTANTE% | findstr /C:"TTL=" > nul
if %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'Servidor ya desplegado en otro nodo (IP %IPFLOTANTE% responde a ping).' -ForegroundColor Yellow"
    powershell -Command "Write-Host 'Saliendo sin realizar cambios.' -ForegroundColor Yellow"
    pause
    exit /b 0
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% no está en uso. Procediendo...' -ForegroundColor Green"
)

:: --- Verificar si hay un docker-compose.yml en paralelo al script ---
if not exist "docker-compose.yml" (
    powershell -Command "Write-Host 'ERROR: No se encontró el archivo docker-compose.yml en el directorio actual.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Ruta actual: %CD%' -ForegroundColor Red"
    pause
    exit /b 1
)

:: --- Actualizar datos del mundo desde GitHub ---
powershell -Command "Write-Host 'Sincronizando datos del mundo desde GitHub (rama main)...' -ForegroundColor Cyan"
git fetch origin main >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo obtener información del repositorio remoto.' -ForegroundColor Red"
    pause
    exit /b 1
)

git reset --hard origin/main >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo aplicar los últimos cambios de GitHub.' -ForegroundColor Red"
    pause
    exit /b 1
) else (
    powershell -Command "Write-Host 'Datos del mundo actualizados correctamente desde GitHub.' -ForegroundColor Green"
)

:: --- Activar IP flotante en la interfaz ZeroTier ---
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { New-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -PrefixLength 16 -AddressFamily IPv4 -ErrorAction Stop | Out-Null } else { Write-Host 'ERROR: No se encontró ninguna interfaz ZeroTier.' -ForegroundColor Red; exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Falló la activación de la IP flotante. Verifique permisos o la interfaz ZeroTier.' -ForegroundColor Red"
    pause
    exit /b 1
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% activada con éxito.' -ForegroundColor Green"
)

:: --- Lanzar servidor Docker Compose ---
powershell -Command "Write-Host 'Iniciando el mundo (Docker Compose)...' -ForegroundColor Magenta -BackgroundColor Black"
echo.
docker compose up -d
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Falló el comando docker compose up -d.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Asegúrese de que Docker esté funcionando y que el archivo docker-compose.yml sea válido.' -ForegroundColor Red"
    pause
    exit /b 1
) else (
    powershell -Command "Write-Host 'Docker Compose iniciado con éxito en segundo plano.' -ForegroundColor Green"
)
echo.
powershell -Command "Write-Host '(El terminal de minecraft tardará 1 minuto en estar disponible a partir de que el servidor arranque).' -ForegroundColor Magenta -BackgroundColor Black"

pause
endlocal