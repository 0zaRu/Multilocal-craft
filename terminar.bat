@echo off
echo Guardando el mundo...

:: Ejecutar comando y capturar salida para verificar errores
docker exec -i mc-server rcon-cli save-all flush > temp.txt 2>&1

:: Verificar si hay error de conexión RCON
findstr /C:"Failed to connect to RCON" /C:"connection refused" temp.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp.txt
    powershell -Command "Write-Host 'Debes esperar unos segundos para que todo se pueda cerrar correcamente.' -ForegroundColor Magenta -BackgroundColor Black"
    powershell -Command "Write-Host 'Debe terminar de cargar el mundo para poder hacer un cierre seguro.' -ForegroundColor Magenta -BackgroundColor Black"
    pause
    exit /b
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