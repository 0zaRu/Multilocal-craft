@echo off
setlocal

:: --- Cambiar al directorio donde está el script (evita quedarse en system32) ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Por favor, haga clic derecho en el archivo .bat y seleccione ''Ejecutar como administrador''.' -ForegroundColor Red"
    pause
    exit /b 1
)

echo Guardando el mundo...

:: --- Verificar conexión RCON y ejecutar comando de guardado ---
docker exec -i mc-server rcon-cli save-all flush > temp.txt 2>&1

findstr /C:"Failed to connect to RCON" /C:"connection refused" temp.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp.txt
    powershell -Command "Write-Host 'ERROR: Falló la conexión RCON con el servidor. Asegúrese de que el servidor está en ejecución y RCON configurado correctamente.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Debe terminar de cargar el mundo para poder hacer un cierre seguro.' -ForegroundColor Magenta -BackgroundColor Black"
    pause
    exit /b
)

:: --- Desactivar IP flotante ---
powershell -Command "Write-Host 'Conexión RCON establecida. Desactivando IP flotante %IPFLOTANTE% para liberarla...' -ForegroundColor Yellow"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -ErrorAction SilentlyContinue | Out-Null } else { Write-Host 'ADVERTENCIA: No se encontró la interfaz ZeroTier para desactivar la IP.' -ForegroundColor Yellow }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: Falló la desactivación de la IP flotante. Puede que ya no estuviera activa o que no se encontrara la interfaz.' -ForegroundColor Yellow"
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% desactivada con éxito.' -ForegroundColor Green"
)

del temp.txt

:: --- Verificación del guardado ---
docker logs --tail 20 mc-server | findstr "Saved the game" > nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 3 > nul
    docker logs --tail 20 mc-server | findstr "Saved the game" > nul
)

echo Guardado completado. Cerrando el servidor...
docker exec -i mc-server rcon-cli stop
echo.
powershell -Command "Write-Host 'Cerrado correctamente.' -ForegroundColor Magenta -BackgroundColor Black"

:: --- Subir cambios a GitHub ---
powershell -Command "Write-Host 'Subiendo cambios del mundo a GitHub...' -ForegroundColor Cyan"

:: Si NO existe el repo Git, mostrar advertencia y saltar backup
if not exist ".git" (
    powershell -Command "Write-Host 'No se encontró repositorio Git en el directorio del script. Omisión del backup.' -ForegroundColor Red"
    goto :EOF
)

git add . >nul 2>&1

set "CHANGES=0"
for /f %%i in ('git status --porcelain') do (
    set "CHANGES=1"
    goto :commit
)

:commit
if "%CHANGES%"=="1" (
    set TIMESTAMP=%DATE% %TIME%
    git commit -m "Backup automático del mundo: %TIMESTAMP%" >nul 2>&1
    git push origin main >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        powershell -Command "Write-Host 'Cambios subidos correctamente a GitHub.' -ForegroundColor Green"
    ) else (
        powershell -Command "Write-Host 'ERROR: Falló el push a GitHub. Verifique conexión o autenticación.' -ForegroundColor Red"
    )
) else (
    powershell -Command "Write-Host 'No hay cambios para subir a GitHub.' -ForegroundColor Yellow"
)

pause
endlocal