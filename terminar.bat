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
    goto :EOF
)

echo Guardando el mundo ...

:: --- Verificar conexión RCON y ejecutar comando de guardado ---
docker exec -i mc-server rcon-cli save-all flush > temp.txt 2>&1
findstr /C:"Failed to connect to RCON" /C:"connection refused" temp.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp.txt
    powershell -Command "Write-Host 'ERROR: No se pudo conectar con el servidor.' -ForegroundColor Red"
    
    :: Comprobar si el contenedor está en ejecución
    docker ps -q --filter "name=mc-server" > temp.txt
    set /p RESULTADO=<temp.txt

    if "%RESULTADO%"=="" (
        powershell -Command "Write-Host 'No se ha encontrado el servidor activo.' -ForegroundColor Red"
        del temp.txt
        goto :pushBackup
    ) else (
        powershell -Command "Write-Host 'Debes esperar unos segundos a que el mundo termine de cargar para cerrarlo de forma segura.' -ForegroundColor Green"
        del temp.txt
        goto :EOF
    )
)
del temp.txt

:: --- Desactivar IP flotante ---
powershell -Command "Write-Host 'Se ha conectado con el servidor.' -ForegroundColor Yellow"
powershell -Command "Write-Host 'Desactivando IP %IPFLOTANTE%' -ForegroundColor Yellow"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -ErrorAction SilentlyContinue | Out-Null } else { Write-Host 'ADVERTENCIA: No se encuentra la interfaz ZeroTier para desactivar la IP.' -ForegroundColor Yellow }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: No se pudo desactivar la IP, probablemente no asignada en este momento.' -ForegroundColor Yellow"
    goto :pushBackup
) else (
    powershell -Command "Write-Host 'IP %IPFLOTANTE% desactivada correctamente.' -ForegroundColor Green"
)

:: --- Verificación del guardado en logs de Docker ---
docker logs --tail 20 mc-server | findstr "Saved the game" > nul
if %ERRORLEVEL% NEQ 0 (
    timeout /t 3 > nul
    docker logs mc-server | findstr "Saved the game" > nul
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ERROR: El servidor no se ha guardado correctamente, vuelva a intentarlo.' -ForegroundColor Red"
        goto :EOF
    ) else (
        powershell -Command "Write-Host 'Mundo guardado correctamente' -ForegroundColor Green"
    )
) else (
    powershell -Command "Write-Host 'Mundo guardado correctamente' -ForegroundColor Green"
)

powershell -Command "Write-Host 'Cerrando el servidor...' -ForegroundColor Yellow"

docker exec -i mc-server rcon-cli stop >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo detener el servidor.' -ForegroundColor Red"
    goto :EOF
) else (
    powershell -Command "Write-Host 'Servidor detenido correctamente.' -ForegroundColor Green"
)

:: --- Flujo normal de backup en GitHub ---
:pushBackup
powershell -Command "Write-Host 'Iniciando backup GitHub...' -ForegroundColor Cyan"

:: Asegurar que estamos en main
git checkout main       >nul 2>&1
git pull origin main    >nul 2>&1

if not exist ".git" (
    powershell -Command "Write-Host 'No hay repositorio Git. No se puede guardar.' -ForegroundColor Yellow"
    goto :EOF
)

git add -A >nul 2>&1
git status --porcelain | findstr . >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    for /f "delims=" %%a in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd_HH-mm\""') do set TS=%%a
    git commit -m "Autobackup: %TS%" >nul 2>&1
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