@echo off
setlocal

:: --- Forzar ejecución en la carpeta del script ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
powershell -Command "Write-Host 'Iniciando el asistente para el servidor de Minecraft...' -ForegroundColor Green"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Necesitas permisos de administrador para continuar.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''iniciar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Pulse cualquier tecla para cerrar la ventana' -ForegroundColor Yellow"
    pause >nul
    goto :END
)

:: --- Verificar si hay un docker-compose.yml en paralelo al script ---
if not exist "docker-compose.yml" (
    powershell -Command "Write-Host 'ERROR: Falta un archivo importante (docker-compose.yml) para iniciar el servidor.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Asegurate de que ''docker-compose.yml'' este en la misma carpeta que este programa: %CD%' -ForegroundColor Red"
    goto :END
)

set ASIGNEDIP=0

:: --- Verificar si la IP flotante está en uso ---
powershell -Command "Write-Host 'Comprobando la configuracion de red para el servidor (IP: %IPFLOTANTE%)...' -ForegroundColor Yellow"
ping -n 1 %IPFLOTANTE% | findstr /C:"TTL=" > nul
if %ERRORLEVEL% EQU 0 (
    :: Comprobar si la IP está asignada a la máquina local
    powershell -Command "$localIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress; if ($localIPs -contains '%IPFLOTANTE%') { Write-Host 'La configuracion de red (IP: %IPFLOTANTE%) ya esta lista en este ordenador.' -ForegroundColor Yellow; exit 0 } else { Write-Host 'ERROR: La direccion de red %IPFLOTANTE% esta siendo usada por otro ordenador. Si el servidor ya esta iniciado en otra maquina, puedes conectarte directamente. Si quieres iniciar el servidor aqui, apaga el otro servidor primero o revisa la configuracion de red.' -ForegroundColor Red; exit 1 }"
    if %ERRORLEVEL% EQU 0 (
        set ASIGNEDIP=1
    ) else (
        goto :END
    )
) else (
    powershell -Command "Write-Host 'La configuracion de red (IP: %IPFLOTANTE%) esta disponible. Preparando para activarla.' -ForegroundColor Green"
)

echo 1
:: --- Actualizar datos del mundo desde GitHub ---
set DOCKERUP=0
set RESULTADO=
echo 2

::Comprobar que mc-server no está en ejecución
docker ps -q --filter "name=mc-server" > temp.txt
set /p RESULTADO=<temp.txt
del temp.txt

echo 3
echo DEBUG: El valor de RESULTADO es [%RESULTADO%]
pause
if "%RESULTADO%"=="" (
    echo 4
    powershell -Command "Write-Host 'Buscando actualizaciones para el mundo del servidor en internet...' -ForegroundColor Cyan"
    echo 5
) else (
    echo 8
    powershell -Command "Write-Host 'El servidor de Minecraft ya esta en marcha. No se buscaran actualizaciones del mundo para no interrumpir.' -ForegroundColor Yellow"
    echo 6
    set DOCKERUP=1
    echo 7
    :: SI asignedip y dockerup, goto END
    
    if "%ASIGNEDIP%"=="1" (
        powershell -Command "Write-Host '¡Todo listo! El servidor de Minecraft esta en linea y configurado en este ordenador. Ya puedes entrar a jugar.' -ForegroundColor Green"
        goto :END
    
    ) else (
        powershell -Command "Write-Host 'El servidor de Minecraft ya esta en marcha. Se omitio la busqueda de actualizaciones.' -ForegroundColor Yellow"
        goto :IPACTIVATE
    )
    
)
echo 9

git fetch origin main >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo conectar a internet para buscar actualizaciones del mundo.' -ForegroundColor Red"
    goto :END
)

@REM git reset --hard origin/main >nul 2>&1
@REM if %ERRORLEVEL% NEQ 0 (
@REM     powershell -Command "Write-Host 'ERROR: Hubo un problema al descargar o aplicar las actualizaciones del mundo.' -ForegroundColor Red"
@REM     goto :END

@REM ) else (
@REM     powershell -Command "Write-Host '¡Mundo actualizado! Se descargaron los ultimos cambios del servidor.' -ForegroundColor Green"
@REM )

:IPACTIVATE
:: --- Activar IP flotante en la interfaz ZeroTier ---
if "%ASIGNEDIP%"=="1" (
    powershell -Command "Write-Host 'La configuracion de red (IP: %IPFLOTANTE%) ya esta activada. Iniciando el servidor de Minecraft...' -ForegroundColor Yellow"
    goto :dockerComposeUp
)

powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' } | Select-Object -First 1; if ($interface) { New-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -PrefixLength 16 -AddressFamily IPv4 -ErrorAction Stop | Out-Null } else { Write-Host 'ERROR: No se encontro el programa de red ZeroTier necesario. Asegurate de que ZeroTier este instalado y en ejecucion.' -ForegroundColor Red; exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo activar la configuracion de red (IP: %IPFLOTANTE%). Comprueba que ZeroTier este funcionando correctamente y que tienes permisos de administrador.' -ForegroundColor Red"
    goto :END
) else (
    powershell -Command "Write-Host 'Configuracion de red (IP: %IPFLOTANTE%) activada correctamente.' -ForegroundColor Green"
)

:dockerComposeUp

if "%DOCKERUP%"=="1" (
    powershell -Command "Write-Host 'El servidor de Minecraft ya esta en marcha. No es necesario iniciarlo de nuevo.' -ForegroundColor Yellow"
    goto :END
)

:: --- Lanzar servidor Docker Compose ---
powershell -Command "Write-Host 'Iniciando el servidor de Minecraft...' -ForegroundColor Magenta -BackgroundColor Black"

echo.
docker compose up -d

if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Hubo un problema al intentar iniciar el servidor de Minecraft con Docker.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Asegurate de que Docker Desktop este abierto y funcionando correctamente.' -ForegroundColor Red"
    goto :END
) else (
    powershell -Command "Write-Host '¡Servidor de Minecraft iniciado con exito!' -ForegroundColor Green"
)
echo.
powershell -Command "Write-Host '(El servidor de Minecraft estara completamente listo para jugar en aproximadamente 1 minuto).' -ForegroundColor Magenta -BackgroundColor Black"

:END

echo.
pause
endlocal