@echo off
setlocal enabledelayedexpansion

:: --- Forzar ejecucion en la carpeta del script ---
cd /d "%~dp0"

:: --- Configuracion ---
set IPFLOTANTE=172.25.254.254
set IP_EN_USO_OTRO_PC=0

:: --- Mensaje de inicio y verificacion de privilegios ---
powershell -Command "Write-Host '--- Asistente para iniciar el Servidor de Minecraft ---' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Necesitas permisos de administrador para continuar.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''iniciar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red -ErrorAction SilentlyContinue"

    goto :END
)

:: --- Verificar si Docker esta disponible ---
powershell -Command "Write-Host 'Comprobando si el programa Docker esta funcionando...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
docker ps >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: El programa Docker no parece estar respondiendo.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegurate de que Docker Desktop este abierto y funcionando correctamente antes de continuar.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Si el problema persiste, reinicia Docker Desktop o el ordenador.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host 'Programa Docker detectado y funcionando.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:: --- Verificar si hay un docker-compose.yml en paralelo al script ---
if not exist "docker-compose.yml" (
    powershell -Command "Write-Host 'ERROR: Falta un archivo importante (docker-compose.yml) para iniciar el servidor.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegurate de que ''docker-compose.yml'' este en la misma carpeta que este programa: %CD%' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar la ventana' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    pause >nul
    goto :END
)

set ASIGNEDIP_HERE=0

:: --- Verificar si la IP flotante esta en uso ---
powershell -Command "Write-Host 'Comprobando la configuracion de red para el servidor (IP: %IPFLOTANTE%)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
ping -n 1 %IPFLOTANTE% > temp_ping.txt 2>&1
findstr /C:"TTL=" temp_ping.txt > nul
if %ERRORLEVEL% EQU 0 (
    del temp_ping.txt >nul 2>&1
    :: Comprobar si la IP esta asignada a la maquina local
    powershell -Command "$localIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress; if ($localIPs -contains '%IPFLOTANTE%') { Write-Host 'INFORMACION: La configuracion de red (IP: %IPFLOTANTE%) ya esta activa en este ordenador.' -ForegroundColor Cyan -ErrorAction SilentlyContinue; exit 0 } else { Write-Host 'ERROR: La direccion de red %IPFLOTANTE% esta siendo usada por OTRO ordenador.' -ForegroundColor Red -ErrorAction SilentlyContinue; Write-Host 'Si el servidor ya esta iniciado en otra maquina, puedes conectarte directamente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; Write-Host 'Si quieres iniciar el servidor AQUI, apaga primero el otro servidor o revisa la configuracion de red.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1 }"
    if %ERRORLEVEL% EQU 0 (
        set ASIGNEDIP_HERE=1
    ) else (
        set IP_EN_USO_OTRO_PC=1
        goto :END
    )
) else (
    del temp_ping.txt >nul 2>&1
    powershell -Command "Write-Host 'La configuracion de red (IP: %IPFLOTANTE%) esta disponible. Se activara si es necesario.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:: --- Verificar estado del servidor Docker ---
set DOCKER_MC_RUNNING=0
set RESULTADO_DOCKER_CHECK=

::Comprobar que mc-server no esta en ejecucion
docker ps -q --filter "name=mc-server" --filter "status=running" > temp_docker_ps.txt
set /p RESULTADO_DOCKER_CHECK=<temp_docker_ps.txt
del temp_docker_ps.txt >nul 2>&1

if not "%RESULTADO_DOCKER_CHECK%"=="" (
    powershell -Command "Write-Host 'INFORMACION: El servidor de Minecraft (contenedor Docker ''mc-server'') ya esta en marcha.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    set DOCKER_MC_RUNNING=1
)

:: --- GESTIÓN DE CASOS ---
:: CASO 5: Todo lanzado en este ordenador
if %DOCKER_MC_RUNNING% EQU 1 (
    if %ASIGNEDIP_HERE% EQU 1 (
        powershell -Command "Write-Host 'Todo listo. El servidor de Minecraft esta en linea y la configuracion de red esta activa en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Ya puedes entrar a jugar.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        goto :END
    ) else (
        :: CASO 2: Contenedor desplegado pero IP no asignada
        powershell -Command "Write-Host 'El servidor de Minecraft esta en marcha, pero la IP %IPFLOTANTE% no esta asignada a este PC.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Se apagara el servidor, se actualizaran los datos y se reiniciara correctamente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        
        :: Detener el servidor Docker primero
        powershell -Command "Write-Host 'Deteniendo el servidor de Minecraft...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        docker stop mc-server >nul 2>&1
        
        :: Esperar a que se detenga completamente
        powershell -Command "Write-Host 'Esperando a que el servidor se detenga...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        timeout /t 5 >nul
        
        :: Actualizar desde GitHub
        powershell -Command "Write-Host 'Actualizando datos del servidor desde GitHub...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        git fetch origin main >nul 2>&1
        if %ERRORLEVEL% EQU 0 (
            git reset --hard origin/main >nul 2>&1
            powershell -Command "Write-Host 'Datos del servidor actualizados correctamente.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        ) else (
            powershell -Command "Write-Host 'ADVERTENCIA: No se pudo conectar a internet para actualizar.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        )
        
        :: Continuar con la activación de IP
        goto :IPACTIVATE
    )
) else (
    :: Docker NO está corriendo (DOCKER_MC_RUNNING es 0)
    if %ASIGNEDIP_HERE% EQU 1 (
        :: CASO 4: IP activa, Docker NO activo. No actualizar, iniciar Docker.
        powershell -Command "Write-Host 'INFORMACION: La IP del servidor (%IPFLOTANTE%) ya esta activa en este ordenador, pero el servidor de Minecraft (Docker) no.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Se procedera a iniciar el servidor de Minecraft directamente, sin actualizar desde GitHub.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        goto :dockerComposeUp
    ) else (
        :: CASO 1 (Docker NO activo, IP NO activa): Actualizar desde Git, luego activar IP.
        powershell -Command "Write-Host 'Buscando actualizaciones para el mundo del servidor en internet (GitHub)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        git fetch origin main >nul 2>&1
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ADVERTENCIA: No se pudo conectar a internet (GitHub) para buscar actualizaciones del mundo.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Se continuara con los datos locales. Si es la primera vez, podria faltar el mundo.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            REM No es un error fatal, podemos intentar iniciar con los datos locales.
        ) else (
            powershell -Command "Write-Host 'Comprobacion de actualizaciones finalizada.' -ForegroundColor Green -ErrorAction SilentlyContinue"

            powershell -Command "Write-Host 'Aplicando actualizaciones del mundo desde GitHub (descartando cambios locales no subidos)...' -ForegroundColor Yellow"
            git reset --hard origin/main >nul 2>&1
            if %ERRORLEVEL% NEQ 0 (
                powershell -Command "Write-Host 'ERROR: Hubo un problema al descargar o aplicar las actualizaciones del mundo.' -ForegroundColor Red"
                goto :END
            ) else (
                powershell -Command "Write-Host 'Mundo actualizado. Se descargaron los ultimos cambios del servidor.' -ForegroundColor Green"
            )
        }
        :: Despues de actualizar (o no) desde Git, proceder a activar la IP
        goto :IPACTIVATE
    )
)


:IPACTIVATE
:: --- Activar IP flotante en la interfaz ZeroTier ---
if %ASIGNEDIP_HERE% EQU 1 (
    powershell -Command "Write-Host 'La configuracion de red (IP: %IPFLOTANTE%) ya esta activa. Procediendo a iniciar el servidor de Minecraft...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    goto :dockerComposeUp
)

powershell -Command "Write-Host 'Activando la configuracion de red (IP: %IPFLOTANTE%) en este ordenador...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
powershell -Command "$interface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' -and $_.Status -eq 'Up' } | Select-Object -First 1; if ($interface) { New-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $interface.ifIndex -PrefixLength 16 -AddressFamily IPv4 -ErrorAction Stop | Out-Null } else { Write-Host 'ERROR: No se encontro el programa de red ZeroTier activo y necesario.' -ForegroundColor Red -ErrorAction SilentlyContinue; Write-Host 'Asegurate de que ZeroTier este instalado, en ejecucion y conectado a tu red.' -ForegroundColor Red -ErrorAction SilentlyContinue; exit 1 }"
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: No se pudo activar la configuracion de red (IP: %IPFLOTANTE%).' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Comprueba que ZeroTier este funcionando correctamente y que tienes permisos de administrador.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host 'Configuracion de red (IP: %IPFLOTANTE%) activada correctamente en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)

:dockerComposeUp

if %DOCKER_MC_RUNNING% EQU 1 (
    powershell -Command "Write-Host 'El servidor de Minecraft ya estaba en marcha. No es necesario iniciarlo de nuevo.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Todo listo. Ya puedes entrar a jugar.' -ForegroundColor Green -ErrorAction SilentlyContinue"
    goto :END
)

:: --- Lanzar servidor Docker Compose ---
powershell -Command "Write-Host 'Iniciando el servidor de Minecraft (puede tardar unos minutos)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"

echo.
docker compose up -d

if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Hubo un problema al intentar iniciar el servidor de Minecraft con Docker.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Asegurate de que Docker Desktop este abierto y funcionando correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Revisa los mensajes de error de Docker en la consola para mas detalles.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    goto :END
) else (
    powershell -Command "Write-Host 'Servidor de Minecraft iniciado con exito.' -ForegroundColor Green -ErrorAction SilentlyContinue"
)
echo.
powershell -Command "Write-Host 'El servidor de Minecraft estara completamente listo para jugar en aproximadamente 1 o 2 minutos.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
powershell -Command "Write-Host 'Puedes cerrar esta ventana o esperar.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"

:END
del temp_*.txt >nul 2>&1 2>nul
echo.
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
pause >nul
endlocal