@echo off
setlocal

:: --- Configuración ---
:: Define la IP flotante que el script intentará gestionar.
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
:: Muestra un mensaje de inicio y comprueba si el script se está ejecutando con privilegios de administrador.
:: 'NET SESSION' es un comando que solo funciona si tienes privilegios elevados.
powershell -Command "Write-Host 'Iniciando script de despliegue de servidor ZeroTier...' -ForegroundColor Green"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Por favor, haga clic derecho en el archivo .bat y seleccione ''Ejecutar como administrador''.' -ForegroundColor Red"
    pause
    exit /b 1
)

:: --- Verificar si la IP flotante está en uso (respuesta a ping) ---
:: Intenta hacer ping a la IP flotante. Si recibe una respuesta (TTL=), asume que ya está en uso.
powershell -Command "Write-Host 'Verificando si la IP flotante %IPFLOTANTE% ya está en uso...' -ForegroundColor Yellow"
ping -n 1 %IPFLOTANTE% | findstr /C:"TTL=" > nul
if %ERRORLEVEL% EQU 0 (
    :: Si el ping es exitoso, la IP ya está en uso. Muestra un mensaje y sale.
    powershell -Command "Write-Host 'Servidor ya desplegado en otro nodo (IP %IPFLOTANTE% responde a ping).' -ForegroundColor Yellow"
    powershell -Command "Write-Host 'Saliendo sin realizar cambios.' -ForegroundColor Yellow"
    pause
    exit /b 0
) else (
    :: Si el ping falla, la IP no está en uso. Continúa con el despliegue.
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% no está en uso. Procediendo...' -ForegroundColor Green"
)

:: --- Activar IP flotante en la interfaz ZeroTier ---
:: Busca la primera interfaz de red que contenga "ZeroTier" en su descripción y le asigna la IP flotante.
:: '-ErrorAction Stop' asegura que PowerShell detenga la ejecución si hay un error y propague el código de error.
:: 'Out-Null' suprime la salida detallada del comando New-NetIPAddress.
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { New-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -PrefixLength 16 -AddressFamily IPv4 -ErrorAction Stop | Out-Null } else { Write-Host 'ERROR: No se encontró ninguna interfaz ZeroTier.' -ForegroundColor Red; exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    :: Si el comando PowerShell anterior falló, muestra un error y sale.
    powershell -Command "Write-Host 'ERROR: Falló la activación de la IP flotante. Verifique permisos o la interfaz ZeroTier.' -ForegroundColor Red"
    pause
    exit /b 1
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% activada con éxito.' -ForegroundColor Green"
)

:: --- Lanzar servidor Docker Compose ---
:: Ejecuta 'docker compose up -d' para iniciar los servicios definidos en tu archivo docker-compose.yml.
powershell -Command "Write-Host 'Iniciando el mundo (Docker Compose)...' -ForegroundColor Magenta -BackgroundColor Black"
echo.
docker compose up -d
if %ERRORLEVEL% NEQ 0 (
    :: Si el comando docker compose falló, muestra un error y sale.
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