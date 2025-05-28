@echo off
setlocal enabledelayedexpansion

:: --- Forzar ejecución en la carpeta del script ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254

:: --- Mensaje de inicio y verificación de privilegios ---
powershell -Command "Write-Host '--- Asistente para iniciar el Servidor de Minecraft ---' -ForegroundColor Magenta -ErrorAction SilentlyContinue"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Necesitas permisos de administrador para continuar.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''iniciar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar la ventana' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    pause >nul
    goto :END
)

:: --- Verificar si Docker está disponible ---
powershell -Command "Write-Host 'Comprobando si el programa Docker está funcionando...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
docker ps >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: El programa Docker no parece estar respondiendo.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegúrate de que Docker Desktop esté abierto y funcionando correctamente antes de continuar.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Si el problema persiste, reinicia Docker Desktop o el ordenador.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host 'Programa Docker detectado y funcionando.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:: --- Verificar si hay un docker-compose.yml en paralelo al script ---
if not exist "docker-compose.yml" (
    powershell -Command "Write-Host 'ERROR: Falta un archivo importante (docker-compose.yml) para iniciar el servidor.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegúrate de que ''docker-compose.yml'' esté en la misma carpeta que este programa: %CD%' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar la ventana' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    pause >nul
    goto :END
)

set ASIGNEDIP_HERE=0

:: --- Verificar si la IP flotante está en uso ---
powershell -Command "Write-Host 'Comprobando la configuración de red para el servidor (IP: %IPFLOTANTE%)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
ping -n 1 %IPFLOTANTE% > temp_ping.txt 2>&1
findstr /C:"TTL=" temp_ping.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp_ping.txt >nul 2>&1
    :: Comprobar si la IP está asignada a la máquina local
    powershell -Command "$localIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress; if ($localIPs -contains '%IPFLOTANTE%') { Write-Host 'INFORMACIÓN: La configuración de red (IP: %IPFLOTANTE%) ya está activa en este ordenador.' -ForegroundColor Blue -ErrorAction SilentlyContinue; exit 0 } else { Write-Host 'ERROR: La dirección de red %IPFLOTANTE% está siendo usada por OTRO ordenador.' -ForegroundColor Red -ErrorAction SilentlyContinue; Write-Host 'Si el servidor ya está iniciado en otra máquina, puedes conectarte directamente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; Write-Host 'Si quieres iniciar el servidor AQUÍ, apaga primero el otro servidor o revisa la configuración de red.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1 }"
    if %ERRORLEVEL% EQU 0 (
        set ASIGNEDIP_HERE=1
    ) else (
        goto :END
    )
) else (
    del temp_ping.txt >nul 2>&1
    powershell -Command "Write-Host 'La configuración de red (IP: %IPFLOTANTE%) está disponible. Se activará si es necesario.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:: --- Actualizar datos del mundo desde GitHub ---
set DOCKER_MC_RUNNING=0
set RESULTADO_DOCKER_CHECK=

::Comprobar que mc-server no está en ejecución
docker ps -q --filter "name=mc-server" --filter "status=running" > temp_docker_ps.txt
set /p RESULTADO_DOCKER_CHECK=<temp_docker_ps.txt
del temp_docker_ps.txt >nul 2>&1

if not "%RESULTADO_DOCKER_CHECK%"=="" (
    powershell -Command "Write-Host 'INFORMACIÓN: El servidor de Minecraft (contenedor Docker ''mc-server'') ya está en marcha.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
    set DOCKER_MC_RUNNING=1
)

if %DOCKER_MC_RUNNING% EQU 1 (
    if %ASIGNEDIP_HERE% EQU 1 (
        powershell -Command "Write-Host '¡Todo listo! El servidor de Minecraft está en línea y la configuración de red está activa en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Ya puedes entrar a jugar.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        goto :END
    ) else (
        powershell -Command "Write-Host 'El servidor de Minecraft ya está en marcha, pero la IP %IPFLOTANTE% no está en este PC. Se intentará activar...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        goto :IPACTIVATE
    )
)

:: Si el Docker no está corriendo, intentamos actualizar desde Git
powershell -Command "Write-Host 'Buscando actualizaciones para el mundo del servidor en internet (GitHub)...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
git fetch origin main >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ADVERTENCIA: No se pudo conectar a internet (GitHub) para buscar actualizaciones del mundo.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Se continuará con los datos locales. Si es la primera vez, podría faltar el mundo.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    :: No es un error fatal, podemos intentar iniciar con los datos locales.
) else (
    powershell -Command "Write-Host 'Comprobación de actualizaciones finalizada.' -ForegroundColor Green -ErrorAction SilentlyContinue"
    :: Aquí podrías añadir git pull o git reset si quieres forzar la actualización.
    :: Por ejemplo, para forzar que los archivos locales coincidan con los de GitHub (descartando cambios locales no subidos):
    :: powershell -Command "Write-Host 'Aplicando actualizaciones del mundo desde GitHub (descartando cambios locales no subidos)...' -ForegroundColor Cyan"
    :: git reset --hard origin/main >nul 2>&1
    :: if %ERRORLEVEL% NEQ 0 (
    ::     powershell -Command "Write-Host 'ERROR: Hubo un problema al descargar o aplicar las actualizaciones del mundo.' -ForegroundColor Red"
    ::     goto :END
    :: ) else (
    ::     powershell -Command "Write-Host '¡Mundo actualizado! Se descargaron los últimos cambios del servidor.' -ForegroundColor Green"
    :: )
)


:IPACTIVATE
:: --- Activar IP flotante en la interfaz ZeroTier ---
if %ASIGNEDIP_HERE% EQU 1 (
    powershell -Command "Write-Host 'La configuración de red (IP: %IPFLOTANTE%) ya está activa. Procediendo a iniciar el servidor de Minecraft...' -ForegroundColor Blue -ErrorAction SilentlyContinue"
    goto :dockerComposeUp
)

powershell -Command "Write-Host 'Activando la configuración de red (IP: %IPFLOTANTE%) en este ordenador...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' -and $_.Status -eq 'Up' } | Select-Object -First 1; if ($interface) { New-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -PrefixLength 16 -AddressFamily IPv4 -ErrorAction Stop | Out-Null } else { Write-Host 'ERROR: No se encontró el programa de red ZeroTier activo y necesario.' -ForegroundColor Red -ErrorAction SilentlyContinue; Write-Host 'Asegúrate de que ZeroTier esté instalado, en ejecución y conectado a tu red.' -ForegroundColor Red -ErrorAction SilentlyContinue; exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo activar la configuración de red (IP: %IPFLOTANTE%).' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Comprueba que ZeroTier esté funcionando correctamente y que tienes permisos de administrador.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host 'Configuración de red (IP: %IPFLOTANTE%) activada correctamente en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:dockerComposeUp

if %DOCKER_MC_RUNNING% EQU 1 (
    powershell -Command "Write-Host 'El servidor de Minecraft ya estaba en marcha. No es necesario iniciarlo de nuevo.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host '¡Todo listo! Ya puedes entrar a jugar.' -ForegroundColor Green -ErrorAction SilentlyContinue"
    goto :END
)

:: --- Lanzar servidor Docker Compose ---
powershell -Command "Write-Host 'Iniciando el servidor de Minecraft (puede tardar unos minutos)...' -ForegroundColor Magenta -ErrorAction SilentlyContinue"

echo.
docker compose up -d

if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Hubo un problema al intentar iniciar el servidor de Minecraft con Docker.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegúrate de que Docker Desktop esté abierto y funcionando correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Revisa los mensajes de error de Docker en la consola para más detalles.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host '¡Servidor de Minecraft iniciado con éxito!' -ForegroundColor Green -ErrorAction SilentlyContinue"
)
echo.
powershell -Command "Write-Host 'El servidor de Minecraft estará completamente listo para jugar en aproximadamente 1 o 2 minutos.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'Puedes cerrar esta ventana o esperar.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"

:END

echo.
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
pause >nul
endlocal