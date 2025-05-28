@echo off
setlocal

:: --- Cambiar al directorio donde está el script (evita quedarse en system32) ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: --- Verificación de privilegios ---
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red"
    goto :pushBackup
)

echo Guardando el mundo...

:: --- Verificar conexión RCON y ejecutar comando de guardado ---
docker exec -i mc-server rcon-cli save-all flush > temp.txt 2>&1
findstr /C:"Failed to connect to RCON" /C:"connection refused" temp.txt > nul
if %ERRORLEVEL% EQU 0 (
    powershell -Command "Write-Host 'ERROR: Falló la conexión RCON con el servidor.' -ForegroundColor Red"
    del temp.txt
    goto :pushBackup
)
del temp.txt

:: --- Desactivar IP flotante ---
powershell -Command "Write-Host 'Conexión RCON establecida. Desactivando IP flotante %IPFLOTANTE% para liberarla...' -ForegroundColor Yellow"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -ErrorAction SilentlyContinue | Out-Null } else { Write-Host 'ADVERTENCIA: No se encontró la interfaz ZeroTier para desactivar la IP.' -ForegroundColor Yellow }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: No se pudo desactivar la IP.' -ForegroundColor Yellow"
    goto :pushBackup
) else (
    powershell -Command "Write-Host 'IP flotante %IPFLOTANTE% desactivada correctamente.' -ForegroundColor Green"
)

:: --- Verificación del guardado en logs de Docker ---
docker logs --tail 20 mc-server | findstr "Saved the game" > nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 3 > nul
    docker logs --tail 20 mc-server | findstr "Saved the game" > nul
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ERROR: El servidor no confirmó el guardado.' -ForegroundColor Red"
        goto :pushBackup
    )
)

echo Cerrando el servidor...
docker exec -i mc-server rcon-cli stop >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo detener el servidor.' -ForegroundColor Red"
    goto :pushBackup
)

powershell -Command "Write-Host 'Cerrado correctamente.' -ForegroundColor Magenta"

:: --- Flujo normal de backup en GitHub ---
:pushBackup
powershell -Command "Write-Host 'Iniciando backup GitHub...' -ForegroundColor Cyan"

:: Asegurar que estamos en main
git checkout main       >nul 2>&1
git pull origin main    >nul 2>&1

if not exist ".git" (
    powershell -Command "Write-Host 'No hay repositorio Git. Omisión del backup.' -ForegroundColor Yellow"
    goto :EOF
)

git add -A >nul 2>&1
git status --porcelain | findstr . >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    for /f "tokens=1-2 delims= " %%A in ('echo %DATE%_%TIME%') do set TS=%%A_%%B
    git commit -m "Backup automático: %TS%" >nul 2>&1
    git push origin main             >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        powershell -Command "Write-Host 'Backup subido correctamente.' -ForegroundColor Green"
    ) else (
        powershell -Command "Write-Host 'Error al subir el backup.' -ForegroundColor Red"
    )
) else (
    powershell -Command "Write-Host 'No hay cambios para subir.' -ForegroundColor Yellow"
)

:EOF

pause
endlocal