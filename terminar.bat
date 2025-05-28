@echo off
setlocal

:: --- Configuración ---
:: Define la IP flotante que el script intentará gestionar.
:: Asegúrate de que esta IP coincida con la que usas en tu script de inicio.
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
:: Muestra un mensaje de inicio y comprueba si el script se está ejecutando con privilegios de administrador.
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Por favor, haga clic derecho en el archivo .bat y seleccione ''Ejecutar como administrador''.' -ForegroundColor Red"
    pause
    exit /b 1
)

echo Guardando el mundo...

:: --- Verificar conexión RCON y ejecutar comando de guardado ---
:: Ejecutar comando save-all flush y capturar salida para verificar errores de conexión RCON.
:: Si la conexión RCON falla, el script mostrará un error y saldrá.
docker exec -i mc-server rcon-cli save-all flush > temp.txt 2>&1

:: Verificar si hay error de conexión RCON
findstr /C:"Failed to connect to RCON" /C:"connection refused" temp.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp.txt
    powershell -Command "Write-Host 'ERROR: Falló la conexión RCON con el servidor. Asegúrese de que el servidor está en ejecución y RCON configurado correctamente.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Debe terminar de cargar el mundo para poder hacer un cierre seguro.' -ForegroundColor Magenta -BackgroundColor Black"
    pause
    exit /b
)

:: --- Desactivar IP flotante (solo si la conexión RCON fue exitosa) ---
:: Elimina la IP flotante de la interfaz ZeroTier.
powershell -Command "Write-Host 'Conexión RCON establecida. Desactivando IP flotante %IPFLOTANTE% para liberarla...' -ForegroundColor Yellow"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -ErrorAction SilentlyContinue | Out-Null } else { Write-Host 'ADVERTENCIA: No se encontró la interfaz ZeroTier para desactivar la IP.' -ForegroundColor Yellow }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: Falló la desactivación de la IP flotante. Puede que ya no estuviera activa o que no se encontrara la interfaz.' -ForegroundColor Yellow"
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% desactivada con éxito.' -ForegroundColor Green"
)

del temp.txt

:: Verificamos que el guardado ha terminado (buscamos mensaje de confirmación)
docker logs --tail 20 mc-server | findstr "Saved the game" > nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 3 > nul
    docker logs --tail 20 mc-server | findstr "Saved the game" > nul
)

echo Guardado completado. Cerrando el servidor...
docker exec -i mc-server rcon-cli stop
echo.

powershell -Command "Write-Host 'Cerrado correctamente.' -ForegroundColor Magenta -BackgroundColor Black"

pause
endlocal