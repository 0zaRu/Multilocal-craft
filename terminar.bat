@echo off
setlocal enabledelayedexpansion

:: --- Cambiar al directorio donde está el script (evita quedarse en system32) ---
cd /d "%~dp0"

:: --- Configuración ---
set IPFLOTANTE=172.25.254.254
set MUNDO_GUARDADO_EXITO=1
set SERVIDOR_DETENIDO_EXITO=1
set DESACTIVACION_IP_EXITO=1

:: --- Verificación de privilegios ---
NET SESSION >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    powershell -Command "Write-Host 'ERROR: Este script debe ejecutarse como administrador.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Por favor, cierra esta ventana, haz clic derecho sobre el archivo ''terminar.bat'' y selecciona ''Ejecutar como administrador''.' -ForegroundColor Red"
    powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar la ventana' -ForegroundColor Yellow"
    pause >nul
    goto :EndScript
)

goto :main

:: -------------------------------------
:: FUNCIONES AUXILIARES
:: -------------------------------------

:desactivarIP
    powershell -Command "Write-Host 'Intentando desactivar la configuración de red del servidor (IP: %IPFLOTANTE%) en este ordenador...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    powershell -Command "$ztInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' -and $_.Status -eq 'Up' } | Select-Object -First 1; if ($ztInterface) { $ipAddress = Get-NetIPAddress -InterfaceIndex $ztInterface.ifIndex -IPAddress '%IPFLOTANTE%' -AddressFamily IPv4 -ErrorAction SilentlyContinue; if ($ipAddress) { Remove-NetIPAddress -IPAddress '%IPFLOTANTE%' -InterfaceIndex $ztInterface.ifIndex -Confirm:$false -ErrorAction SilentlyContinue | Out-Null; $checkIp = Get-NetIPAddress -InterfaceIndex $ztInterface.ifIndex -IPAddress '%IPFLOTANTE%' -AddressFamily IPv4 -ErrorAction SilentlyContinue; if (!$checkIp) { Write-Host 'Configuración de red (IP: %IPFLOTANTE%) desactivada correctamente en este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue; exit 0; } else { Write-Host 'ADVERTENCIA: No se pudo confirmar la desactivación de la IP %IPFLOTANTE%. Puede que siga activa.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1; } } else { Write-Host 'INFORMACIÓN: La configuración de red (IP: %IPFLOTANTE%) no estaba activa en este ordenador.' -ForegroundColor Blue -ErrorAction SilentlyContinue; exit 0; } } else { Write-Host 'ADVERTENCIA: No se encontró el programa de red ZeroTier activo. No se pudo gestionar la IP.' -ForegroundColor Yellow -ErrorAction SilentlyContinue; exit 1; }"
    set DESACTIVACION_IP_EXITO=%ERRORLEVEL%
goto :EOF

:guardarMundo
    powershell -Command "Write-Host 'Guardando el progreso del mundo de Minecraft...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    docker exec -i mc-server rcon-cli save-all flush > temp_rcon.txt 2>&1
    findstr /C:"Failed to connect to RCON" /C:"connection refused" /C:"No such container" temp_rcon.txt > nul
    if %ERRORLEVEL% EQU 0 (
        del temp_rcon.txt >nul 2>&1
        powershell -Command "Write-Host 'ERROR: No se pudo conectar con el servidor de Minecraft para guardar el mundo.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Esto puede pasar si el servidor no estaba completamente iniciado o hay un problema interno. El progreso podría no guardarse.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        set MUNDO_GUARDADO_EXITO=1
        goto :EOF
    )
    del temp_rcon.txt >nul 2>&1
    powershell -Command "Write-Host 'Comando de guardado enviado. Verificando que todo se haya guardado bien...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    
    timeout /t 3 > nul :: Dar tiempo a que el log se actualice
    docker logs --tail 30 mc-server 2>&1 | findstr /C:"Saved the game" /C:"Guardado completo" > nul
    if %ERRORLEVEL% NEQ 0 (
        timeout /t 5 > nul :: Segundo intento con más tiempo y logs más amplios
        docker logs --since 2m mc-server 2>&1 | findstr /C:"Saved the game" /C:"Guardado completo" > nul
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ERROR: No se pudo confirmar que el mundo de Minecraft se haya guardado correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Es recomendable revisar los registros del servidor manualmente si el progreso es importante.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            set MUNDO_GUARDADO_EXITO=1
            goto :EOF
        )
    )
    powershell -Command "Write-Host '¡Progreso del mundo de Minecraft guardado con éxito!' -ForegroundColor Green -ErrorAction SilentlyContinue"
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
        powershell -Command "Write-Host 'ADVERTENCIA: El comando para apagar el servidor directamente (`docker stop mc-server`) falló. Puede que ya estuviera apagado.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )
    
    powershell -Command "Write-Host 'Esperando a que el servidor se apague completamente (puede tardar hasta 30 segundos)...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    for /L %%i in (1,1,30) do (
        docker ps -q --filter "name=mc-server" --filter "status=running" > temp_docker_stop_check.txt
        set /p DOCKER_STILL_RUNNING=<temp_docker_stop_check.txt
        del temp_docker_stop_check.txt >nul 2>&1
        if "!DOCKER_STILL_RUNNING!"=="" (
            powershell -Command "Write-Host '¡Servidor de Minecraft apagado correctamente!' -ForegroundColor Green -ErrorAction SilentlyContinue"
            set SERVIDOR_DETENIDO_EXITO=0
            goto :EOF
        )
        timeout /t 1 > nul
    )
    powershell -Command "Write-Host 'ERROR: El servidor de Minecraft no se apagó en el tiempo esperado.' -ForegroundColor Red -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Puede que necesites apagarlo manualmente usando el programa Docker Desktop o contactar al administrador.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    set SERVIDOR_DETENIDO_EXITO=1
goto :EOF

:pushBackupGit
    powershell -Command "Write-Host 'Iniciando copia de seguridad de los datos del mundo en internet (GitHub)...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"

    if not exist ".git" (
        powershell -Command "Write-Host 'ERROR: No se encuentra la configuración de Git en esta carpeta. Parece que esta carpeta no está preparada para copias de seguridad en GitHub.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'No se puede realizar la copia de seguridad.' -ForegroundColor Red -ErrorAction SilentlyContinue"
        goto :EOF
    )

    powershell -Command "Write-Host 'Preparando para la copia de seguridad: actualizando con la última versión de internet...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    git checkout main >NUL 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: No se pudo cambiar a la rama principal (`main`) para la copia de seguridad. Puede haber cambios sin guardar en otra rama.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Se intentará continuar, pero es recomendable revisar el estado de Git manualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )

    git pull origin main >NUL 2>&1
    if %ERRORLEVEL% NEQ 0 (
        powershell -Command "Write-Host 'ADVERTENCIA: Falló la actualización desde internet (`git pull origin main`).' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'Puede haber conflictos o problemas de conexión. Revisa manualmente antes de futuros cambios.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )
    
    powershell -Command "Write-Host 'Revisando si hay cambios en los archivos del mundo para guardar...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
    git add -A >NUL 2>&1
    
    git status --porcelain | findstr . > NUL
    if %ERRORLEVEL% EQU 0 (
        for /f "delims=" %%a in ('powershell -Command "Get-Date -Format \"yyyy-MM-dd HH:mm:ss\""') do set TIMESTAMP=%%a
        powershell -Command "Write-Host ('Guardando los cambios detectados con fecha: !TIMESTAMP!') -ForegroundColor Cyan -ErrorAction SilentlyContinue"
        git commit -m "Copia de seguridad automática: !TIMESTAMP!" >NUL 2>&1
        if %ERRORLEVEL% NEQ 0 (
            powershell -Command "Write-Host 'ERROR: Falló al guardar los cambios localmente (`git commit`).' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Puede que no haya cambios reales para guardar, o haya un problema con tu configuración de Git (nombre/email).' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Revisa el estado de Git (`git status`) y tu configuración manualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            goto :EOF
        )
        
        powershell -Command "Write-Host 'Subiendo la copia de seguridad a internet (GitHub)...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
        git push origin main >NUL 2>&1
        if %ERRORLEVEL% EQU 0 (
            powershell -Command "Write-Host '¡Copia de seguridad subida correctamente a GitHub!' -ForegroundColor Green -ErrorAction SilentlyContinue"
        ) else (
            powershell -Command "Write-Host 'ERROR: Falló la subida de la copia de seguridad a GitHub (`git push`).' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Asegúrate de tener conexión a internet, los permisos correctos y que no haya conflictos que requieran una actualización (`pull`) manual.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        )
    ) else (
        powershell -Command "Write-Host 'No hay cambios nuevos en los archivos del mundo para subir a la copia de seguridad.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
    )
goto :EOF

:: -------------------------------------
:: SCRIPT PRINCIPAL
:: -------------------------------------
:main
    powershell -Command "Write-Host '--- Asistente para apagar el Servidor de Minecraft ---' -ForegroundColor Magenta -ErrorAction SilentlyContinue"
    powershell -Command "Write-Host 'Comprobando el estado actual del servidor y la red...' -ForegroundColor Cyan -ErrorAction SilentlyContinue"

    :: Comprobar si la IP flotante está asignada a este PC en la interfaz ZeroTier
    powershell -Command "$ipConfig = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -eq '%IPFLOTANTE%' }; $ztInterface = Get-NetAdapter | Where-Object { $_.InterfaceDescription -like '*ZeroTier*' -and $_.Status -eq 'Up' }; if ($ipConfig -and $ztInterface -and ($ipConfig.InterfaceIndex -eq $ztInterface.ifIndex)) { exit 0 } else { exit 1 }"
    set IP_ASIGNADA_AQUI=%ERRORLEVEL%

    :: Comprobar si el servicio Docker está disponible y el estado del contenedor
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
        powershell -Command "Write-Host 'ERROR: El programa Docker no parece estar funcionando (Docker Desktop podría estar cerrado o el servicio detenido).' -ForegroundColor Red -ErrorAction SilentlyContinue"
        powershell -Command "Write-Host 'No se podrá apagar el servidor de Minecraft de forma normal si estaba funcionando.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
    )

    :: --- Lógica principal basada en el estado detectado ---

    if %DOCKER_SERVICE_OK% EQU 0 (
        powershell -Command "Write-Host 'Debido a problemas con Docker, solo se intentará desactivar la IP del servidor (si está en este PC) y hacer una copia de seguridad de los datos locales.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        if %IP_ASIGNADA_AQUI% EQU 0 (
            powershell -Command "Write-Host 'INFORMACIÓN: La IP del servidor (%IPFLOTANTE%) está configurada en este ordenador. Se intentará desactivar.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
            call :desactivarIP
        ) else (
            powershell -Command "Write-Host 'INFORMACIÓN: La IP del servidor (%IPFLOTANTE%) NO está configurada en este ordenador (o no se pudo verificar).' -ForegroundColor Blue -ErrorAction SilentlyContinue"
        )
        powershell -Command "Write-Host 'Intentando realizar copia de seguridad de los archivos locales por si hay cambios...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
        call :pushBackupGit
        goto :EndScript
    )

    :: Docker está OK, procedemos con la lógica completa
    if %IP_ASIGNADA_AQUI% EQU 0 (
        if %DOCKER_ACTIVO% EQU 1 (
            :: Caso 1: IP asignada Y Docker en ejecución (Todo arrancado)
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) está configurada en este ordenador y el servidor de Minecraft está funcionando.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Iniciando apagado completo: Guardar progreso, desactivar IP, apagar servidor y hacer copia de seguridad.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            call :guardarMundo
            if %MUNDO_GUARDADO_EXITO% NEQ 0 (
                powershell -Command "Write-Host 'CRÍTICO: El progreso del mundo de Minecraft no se guardó correctamente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                powershell -Command "Write-Host 'Para evitar pérdida de datos, se aborta el resto del proceso. Por favor, revisa el servidor y los logs manualmente.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                powershell -Command "Write-Host 'Vuelve a intentarlo cuando el problema de guardado esté solucionado.' -ForegroundColor Red -ErrorAction SilentlyContinue"
                goto :EndScript
            )

            call :desactivarIP
            REM El mensaje de éxito/error de desactivarIP se da dentro de la función. Continuamos igualmente.

            call :detenerServidorDocker
            if %SERVIDOR_DETENIDO_EXITO% NEQ 0 (
                 powershell -Command "Write-Host 'ADVERTENCIA: El servidor de Minecraft no se apagó correctamente según la verificación. La copia de seguridad se intentará igualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            )
            
            call :pushBackupGit

        ) else (
            :: Caso 3: IP asignada Y Docker NO en ejecución
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) está configurada en este ordenador, pero el servidor de Minecraft NO está funcionando.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Se procederá a desactivar la IP en este ordenador y a realizar una copia de seguridad de los datos.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            call :desactivarIP
            call :pushBackupGit
        )
    ) else (
        if %DOCKER_ACTIVO% EQU 1 (
            :: Caso 4: IP NO asignada Y Docker en ejecución
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) NO está configurada en este ordenador, pero el servidor de Minecraft SÍ está funcionando.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'ADVERTENCIA: Esta es una situación inusual. El servidor está activo, pero este ordenador no es el que gestiona su IP pública.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            
            powershell -Command "Write-Host 'Se intentará guardar el progreso del mundo antes de apagar el servidor (recomendado)...' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            call :guardarMundo
            if %MUNDO_GUARDADO_EXITO% NEQ 0 (
                powershell -Command "Write-Host 'ADVERTENCIA: No se pudo guardar el progreso del mundo. El servidor se apagará igualmente.' -ForegroundColor Yellow -ErrorAction SilentlyContinue"
            )

            call :detenerServidorDocker
            REM Mensaje de éxito/error dentro de la función.

            powershell -Command "Write-Host 'IMPORTANTE: El servidor de Minecraft se ha apagado.' -ForegroundColor Green -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Dado que la IP del servidor no estaba gestionada por este ordenador, NO se realizará una copia de seguridad automática desde aquí.' -ForegroundColor Red -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'CONTACTAR AL ADMINISTRADOR: Es crucial verificar la integridad de los datos y la correcta gestión de la IP del servidor. Puede que la copia de seguridad deba hacerse desde el ordenador que SÍ tiene la IP asignada.' -ForegroundColor Red -ErrorAction SilentlyContinue"

        ) else (
            :: Caso 2: IP NO asignada Y Docker NO en ejecución (Todo cerrado)
            powershell -Command "Write-Host 'Detectado: La IP del servidor (%IPFLOTANTE%) NO está configurada en este ordenador y el servidor de Minecraft NO está funcionando.' -ForegroundColor Blue -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'El sistema parece estar ya apagado. No se requieren acciones sobre el servidor o la IP desde este ordenador.' -ForegroundColor Green -ErrorAction SilentlyContinue"
            powershell -Command "Write-Host 'Se intentará una copia de seguridad por si hay cambios locales en los archivos del mundo.' -ForegroundColor Cyan -ErrorAction SilentlyContinue"
            call :pushBackupGit
        )
    )

:EndScript
del temp_*.txt >nul 2>&1 2>nul
powershell -Command "Write-Host '--- Proceso de apagado del servidor finalizado. ---' -ForegroundColor Magenta -ErrorAction SilentlyContinue"
echo.
powershell -Command "Write-Host 'Pulsa cualquier tecla para cerrar esta ventana.' -ForegroundColor Yellow"
pause >nul
endlocal