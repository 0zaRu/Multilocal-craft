@echo off
setlocal

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: Cambiar al directorio del repositorio (ajusta la ruta)
cd /d "%~dp0"

if ERRORLEVEL 1 (
    powershell -Command "Write-Host 'ERROR: No se pudo cambiar al directorio del repositorio.' -ForegroundColor Red"
    pause
    exit /b 1
)

:: --- Verificación de privilegios ---
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
del temp.txt

:: --- Desactivar IP flotante ---
powershell -Command "Write-Host 'Conexión RCON establecida. Desactivando IP flotante %IPFLOTANTE%...' -ForegroundColor Yellow"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -ErrorAction SilentlyContinue | Out-Null } else { Write-Host 'ADVERTENCIA: No se encontró la interfaz ZeroTier.' -ForegroundColor Yellow }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: Falló la desactivación de la IP flotante.' -ForegroundColor Yellow"
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% desactivada con éxito.' -ForegroundColor Green"
)

:: --- Confirmar guardado en logs de Docker ---
docker logs --tail 20 mc-server | findstr "Saved the game" > nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 3 > nul
    docker logs --tail 20 mc-server | findstr "Saved the game" > nul
)

echo Guardado completado. Cerrando el servidor...
docker exec -i mc-server rcon-cli stop
echo.

powershell -Command "Write-Host 'Cerrado correctamente.' -ForegroundColor Magenta -BackgroundColor Black"

:: --- Cambiar a rama main ---
git checkout main
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo cambiar a la rama main.' -ForegroundColor Red"
    pause
    exit /b 1
)

:: --- Mostrar rama actual y remotos ---
git branch
git remote -v

:: --- Detectar cambios ---
set CHANGES=0
git status --porcelain | findstr /R /C:"^." > nul
if %ERRORLEVEL% EQU 0 (
    set CHANGES=1
)

if "%CHANGES%"=="1" (
    echo Cambios detectados. Añadiendo y comiteando...
    git add -A
    set TIMESTAMP=%DATE% %TIME%
    git commit -m "Backup automático del mundo: %TIMESTAMP%"
    
    echo Ejecutando git push...
    git push origin main > push_log.txt 2>&1
    if %ERRORLEVEL% EQU 0 (
        powershell -Command "Write-Host 'Cambios subidos correctamente a GitHub.' -ForegroundColor Green"
    ) else (
        powershell -Command "Write-Host 'ERROR: Falló el push a GitHub. Revisa push_log.txt para detalles.' -ForegroundColor Red"
        type push_log.txt
        pause
        exit /b 1
    )
) else (
    powershell -Command "Write-Host 'No hay cambios para subir a GitHub.' -ForegroundColor Yellow"
)

pause
endlocal