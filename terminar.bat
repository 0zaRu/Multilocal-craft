@echo off
setlocal enabledelayedexpansion

:: --- Cambiar al directorio donde esta el script (evita quedarse en system32) ---
cd /d "%~dp0"

:: --- Configuracion ---
set IPFLOTANTE=172.25.254.254
set MUNDO_GUARDADO_EXITO=1
set SERVIDOR_DETENIDO_EXITO=1
set DESACTIVACION_IP_EXITO=1

:: --- Verificacion de privilegios ---
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''terminar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar la ventana' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    pause >nul
    goto :EndScript
)

goto :main

:: -------------------------------------
:: FUNCIONES AUXILIARES
:: -------------------------------------

:desactivarIP
    powershell -Command "Write-Host 'Intentando desactivar la configuracion de red del servidor (IP: %IPFLOTANTE%) en este ordenador...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    powershell -Command "$ztInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' -and $_.Status -eq 'Up' } | Select-Object -First 1; if ($ztInterface) { $ipAddress = Get-NetIPAddress -InterfaceIndex $ztInterface.ifIndex -IPAddress '%IPFLOTANTE%' -AddressFamily IPv4 -ErrorAction SilentlyContinue; if ($ipAddress) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $ztInterface.ifIndex -Confirm:$false -ErrorAction SilentlyContinue | Out-Null; $checkIp = Get-NetIPAddress -InterfaceIndex $ztInterface.ifIndex -IPAddress '%IPFLOTANTE%' -AddressFamily IPv4 -ErrorAction SilentlyContinue; if (!$checkIp) { Write-Host 'Configuracion de red (IP: %IPFLOTANTE%) desactivada correctamente en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue; exit 0; } else { Write-Host 'ADVERTENCIA: No se pudo confirmar la desactivacion de la IP %IPFLOTANTE%. Puede que siga activa.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1; } } else { Write-Host 'INFORMACION: La configuracion de red (IP: %IPFLOTANTE%) no estaba activa en este ordenador.' -ForegroundColor Cyan -ErrorAction SilentlyContinue; exit 0; } } else { Write-Host 'ADVERTENCIA: No se encontro el programa de red ZeroTier activo. No se pudo gestionar la IP.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1; }"
    set DESACTIVACION_IP_EXITO=%ERRORLEVEL%
goto :EOF

:guardarMundo
    powershell -Command "Write-Host 'Guardando el progreso del mundo de Minecraft...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    docker exec -i mc-server rcon-cli save-all flush > temp_rcon.txt 2>&1
    findstr /C:"Failed to connect to RCON" /C:"connection refused" /C:"No such container" temp_rcon.txt > nul
    if %ERRORLEVEL% EQU 0 (
        del temp_rcon.txt >nul 2>&1
        powershell -Command "Write-Host 'ERROR: No se pudo conectar con el servidor de Minecraft para guardar el mundo.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Esto puede pasar si el servidor no estaba completamente iniciado o hay un problema interno. El progreso podria no guardarse.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        set MUNDO_GUARDADO_EXITO=1
        goto :EOF
    )
    del temp_rcon.txt >nul 2>&1
    powershell -Command "Write-Host 'Comando de guardado enviado. Verificando que todo se haya guardado bien...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    
    timeout /t 3 > nul :: Dar tiempo a que el log se actualice
    docker logs --tail 30 mc-server 2>&1 | findstr /C:"Saved the game" /C:"Guardado completo" > nul
    if %ERRORLEVEL% NEQ 0 (
        timeout /t 5 > nul :: Segundo intento con mas tiempo y logs mas amplios
        docker logs --since 2m mc-server 2>&1 | findstr /C:"Saved the game" /C:"Guardado completo" > nul
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ERROR: No se pudo confirmar que el mundo de Minecraft se haya guardado correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Es recomendable revisar los registros del servidor manualmente si el progreso es importante.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            set MUNDO_GUARDADO_EXITO=1
            goto :EOF
        )
    )
    powershell -Command "Write-Host 'Progreso del mundo de Minecraft guardado con exito.' -ForegroundColor Green -ErrorAction SilentlyContinue"
    set MUNDO_GUARDADO_EXITO=0
goto :EOF

:detenerServidorDocker
    powershell -Command "Write-Host 'Apagando el servidor de Minecraft de forma segura...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    docker exec -i mc-server rcon-cli stop >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: No se pudo usar el comando normal para apagar el servidor (puede que ya estuviera apagado o hubiera un problema).' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Intentando apagarlo directamente...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )

    docker stop mc-server >nul 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: El comando para apagar el servidor directamente (`docker stop mc-server`) fallo. Puede que ya estuviera apagado.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )
    
    powershell -Command "Write-Host 'Esperando a que el servidor se apague completamente (puede tardar hasta 30 segundos)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    for /L %%i in (1,1,30) do (
        docker ps -q --filter "name=mc-server" --filter "status=running" > temp_docker_stop_check.txt
        set /p DOCKER_STILL_RUNNING=<temp_docker_stop_check.txt
        del temp_docker_stop_check.txt >nul 2>&1
        if "!DOCKER_STILL_RUNNING!"=="" (
            powershell -Command "Write-Host 'Servidor de Minecraft apagado correctamente.' -ForegroundColor Green -ErrorAction SilentlyContinue"
            set SERVIDOR_DETENIDO_EXITO=0
            goto :EOF
        )
        timeout /t 1 > nul
    )
    powershell -Command "Write-Host 'ERROR: El servidor de Minecraft no se apago en el tiempo esperado.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Puede que necesites apagarlo manualmente usando el programa Docker Desktop o contactar al administrador.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    set SERVIDOR_DETENIDO_EXITO=1
goto :EOF

:pushBackupGit
    powershell -Command "Write-Host 'Iniciando copia de seguridad de los datos del mundo en internet (GitHub)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"

    if not exist ".git" (
        powershell -Command "Write-Host 'ERROR: No se encuentra la configuracion de Git en esta carpeta. Parece que esta carpeta no esta preparada para copias de seguridad en GitHub.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'No se puede realizar la copia de seguridad.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        goto :EOF
    )

    powershell -Command "Write-Host 'Preparando para la copia de seguridad: actualizando con la ultima version de internet...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    git checkout main >NUL 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: No se pudo cambiar a la rama principal (`main`) para la copia de seguridad. Puede haber cambios sin guardar en otra rama.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Se intentara continuar, pero es recomendable revisar el estado de Git manualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )

    git pull origin main >NUL 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: Fallo la actualizacion desde internet (`git pull origin main`).' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Puede haber conflictos o problemas de conexion. Revisa manualmente antes de futuros cambios.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )
    
    powershell -Command "Write-Host 'Revisando si hay cambios en los archivos del mundo para guardar...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    git add -A >NUL 2>&1
    
    git status --porcelain | findstr . > NUL
    if %ERRORLEVEL% EQU 0 (
        for /f "delims=" %%a in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set TIMESTAMP=%%a
        powershell -Command "Write-Host ('Guardando los cambios detectados con fecha: !TIMESTAMP!') -ForegroundColor Cyan -ErrorAction SilentlyContinue"
        git commit -m "Copia de seguridad automatica: !TIMESTAMP!" >NUL 2>&1
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ERROR: Fallo al guardar los cambios localmente (`git commit`).' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Puede que no haya cambios reales para guardar, o haya un problema con tu configuracion de Git (nombre/email).' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Revisa el estado de Git (`git status`) y tu configuracion manualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            goto :EOF
        )
        
        powershell -Command "Write-Host 'Subiendo la copia de seguridad a internet (GitHub)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        git push origin main >NUL 2>&1
        if %ERRORLEVEL% EQU 0 (
            powershell -Command "Write-Host 'Copia de seguridad subida correctamente a GitHub.' -ForegroundColor Green -ErrorAction SilentlyContinue"
        ) else (
            powershell -Command "Write-Host 'ERROR: Fallo la subida de la copia de seguridad a GitHub (`git push`).' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Asegurate de tener conexion a internet, los permisos correctos y que no haya conflictos que requieran una actualizacion (`pull`) manual.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        )
    ) else (
        powershell -Command "Write-Host 'No hay cambios nuevos en los archivos del mundo para subir a la copia de seguridad.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    )
goto :EOF

:: -------------------------------------
:: SCRIPT PRINCIPAL
:: -------------------------------------
:main
    powershell -Command "Write-Host '--- Asistente para apagar el Servidor de Minecraft ---' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Comprobando el estado actual del servidor y la red...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"

    :: Comprobar si la IP flotante esta asignada a este PC
    powershell -Command "$localIPs = Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress; if ($localIPs -contains '%IPFLOTANTE%') { exit 0 } else { exit 1 }"
    set IP_ASIGNADA_AQUI=%ERRORLEVEL%

    :: Comprobar si el servicio Docker esta disponible y el estado del contenedor
    set DOCKER_ACTIVO=0
    set DOCKER_SERVICE_OK=0
    docker ps >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        set DOCKER_SERVICE_OK=1
        docker ps -q --filter "name=mc-server" --filter "status=running" > temp_docker_check.txt
        set /p DOCKER_ID=<temp_docker_check.txt
        del temp_docker_check.txt >nul 2>&1
        if not "!DOCKER_ID!"=="" set DOCKER_ACTIVO=1
    ) else (
        powershell -Command "Write-Host 'ERROR: El programa Docker no parece estar funcionando (Docker Desktop podria estar cerrado o el servicio detenido).' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'No se podra apagar el servidor de Minecraft de forma normal si estaba funcionando.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )

    :: --- Logica principal basada en el estado detectado ---

    if %DOCKER_SERVICE_OK% EQU 0 (
        powershell -Command "Write-Host 'Debido a problemas con Docker, solo se intentara desactivar la IP del servidor (si esta en este PC) y hacer una copia de seguridad de los datos locales.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        if %IP_ASIGNADA_AQUI% EQU 0 (
            powershell -Command "Write-Host 'INFORMACION: La IP del servidor (%IPFLOTANTE%) esta configurada en este ordenador. Se intentara desactivar.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            call :desactivarIP
        ) else (
            powershell -Command "Write-Host 'INFORMACION: La IP del servidor (%IPFLOTANTE%) NO esta configurada en este ordenador (o no se pudo verificar).' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
        )
        powershell -Command "Write-Host 'Intentando realizar copia de seguridad de los archivos locales por si hay cambios...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        call :pushBackupGit
        goto :EndScript
    )

    :: Docker esta OK, procedemos con la logica completa
    if %IP_ASIGNADA_AQUI% EQU 0 (
        if %DOCKER_ACTIVO% EQU 1 (
            :: Caso 1: IP asignada Y Docker en ejecucion (Todo arrancado)
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) esta configurada en este ordenador y el servidor de Minecraft esta funcionando.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Iniciando apagado completo: Guardar progreso, desactivar IP, apagar servidor y hacer copia de seguridad.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            call :guardarMundo
            if %MUNDO_GUARDADO_EXITO% NEQ 0 (
                powershell -Command "Write-Host 'CRITICO: El progreso del mundo de Minecraft no se guardo correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                powershell -Command "Write-Host 'Para evitar perdida de datos, se aborta el resto del proceso. Por favor, revisa el servidor y los logs manualmente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                powershell -Command "Write-Host 'Vuelve a intentarlo cuando el problema de guardado este solucionado.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                goto :EndScript
            )

            call :desactivarIP
            REM El mensaje de exito/error de desactivarIP se da dentro de la funcion. Continuamos igualmente.

            call :detenerServidorDocker
            if %SERVIDOR_DETENIDO_EXITO% NEQ 0 (
                 powershell -Command "Write-Host 'ADVERTENCIA: El servidor de Minecraft no se apago correctamente segun la verificacion. La copia de seguridad se intentara igualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            )
            
            call :pushBackupGit

        ) else (
            :: Caso 3: IP asignada Y Docker NO en ejecucion
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) esta configurada en este ordenador, pero el servidor de Minecraft NO esta funcionando.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Se procedera a desactivar la IP en este ordenador y a realizar una copia de seguridad de los datos.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            call :desactivarIP
            call :pushBackupGit
        )
    ) else (
        if %DOCKER_ACTIVO% EQU 1 (
            :: Caso 4: IP NO asignada Y Docker en ejecucion
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) NO esta configurada en este ordenador, pero el servidor de Minecraft SI esta funcionando.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'ADVERTENCIA: Esta es una situacion inusual. El servidor esta activo, pero este ordenador no es el que gestiona su IP publica.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            powershell -Command "Write-Host 'Se procedera a apagar el servidor de Minecraft directamente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            REM No se guarda el mundo en este caso, segun solicitud.
            call :detenerServidorDocker
            REM Mensaje de exito/error dentro de la funcion.

            powershell -Command "Write-Host 'IMPORTANTE: El servidor de Minecraft se ha apagado.' -ForegroundColor Green -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Dado que la IP del servidor no estaba gestionada por este ordenador, NO se guardo el mundo ni se realizara una copia de seguridad automatica desde aqui.' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'CONTACTAR AL ADMINISTRADOR: Es crucial verificar la integridad de los datos y la correcta gestion de la IP del servidor. La copia de seguridad debera hacerse desde el ordenador que SI tiene la IP asignada, despues de asegurar que el mundo este guardado.' -ForegroundColor Red -ErrorAction SilentlyContinue"

        ) else (
            :: Caso 2: IP NO asignada Y Docker NO en ejecucion (Todo cerrado)
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) NO esta configurada en este ordenador y el servidor de Minecraft NO esta funcionando.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'El sistema parece estar ya apagado. No se requieren acciones sobre el servidor o la IP desde este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'No se realizara ninguna accion adicional.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            REM No se realiza copia de seguridad en este caso, segun solicitud.
        )
    )

:EndScript
del temp_*.txt >nul 2>&1 2>nul
powershell -Command "Write-Host '--- Proceso de apagado del servidor finalizado. ---' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
echo.
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
pause >nul
endlocal