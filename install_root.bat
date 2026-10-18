@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "LOG=%SCRIPT_DIR%root_install.log"
set "IMG=%USERPROFILE%\magisk_patched.img"
set "REMOTE_IMG=/sdcard/Download/magisk_patched.img"
set "MAX_WAIT=40"
set "MIN_IMG_SIZE=16777216"
set "DEBUG=0"
set "MODE=NORMAL"
set "MODE_SPECIFIED=0"

if /I "%~1"=="--debug" set "DEBUG=1"
if /I "%~1"=="--simulator" (
	set "MODE=SIMULATOR"
	set "MODE_SPECIFIED=1"
)
if /I "%~1"=="--dry-run" (
	set "MODE=SIMULATOR"
	set "MODE_SPECIFIED=1"
)

call :init_log
if "%MODE_SPECIFIED%"=="0" call :show_mode_menu
call :check_tool adb || goto :fatal
call :check_tool fastboot || goto :fatal
call :check_adb_device || goto :fatal
call :run "Verificando imagen remota" adb shell ls "%REMOTE_IMG%" || goto :fatal

echo [*] Se flasheara boot_a y boot_b con %IMG%
choice /c SN /n /m "[?] Continuar? [S/N]: "
if errorlevel 2 (
	echo [!] Operacion cancelada por el usuario.
	>>"%LOG%" echo [INFO] %DATE% %TIME% - Operacion cancelada por el usuario
	pause
	exit /b 0
)

call :run "Extrayendo imagen desde el telefono" adb pull "%REMOTE_IMG%" "%IMG%" || goto :fatal
if "%MODE%"=="NORMAL" (
	if not exist "%IMG%" (
		call :log_error "La imagen no se guardo en %IMG%"
		goto :fatal
	)
) else (
	if not exist "%IMG%" (
		echo [SIM] Nota: Archivo no existe en simulador (esto es normal)
		>>"%LOG%" echo [SIM] Nota: Archivo no existe en simulador
	)
)

if exist "%IMG%" (
	for %%I in ("%IMG%") do set "IMG_SIZE=%%~zI"
	if !IMG_SIZE! lss %MIN_IMG_SIZE% (
		if "%MODE%"=="NORMAL" (
			call :log_error "Tamano de imagen sospechoso (!IMG_SIZE! bytes). Verifica que magisk_patched.img sea correcto"
			goto :fatal
		)
	)
	for /f "usebackq delims=" %%H in (`powershell -NoProfile -Command "try { (Get-FileHash -Algorithm SHA256 -LiteralPath '%IMG%' -ErrorAction Stop).Hash } catch { echo ERROR }"`) do (
		if not "%%H"=="ERROR" (
			if not defined IMG_HASH set "IMG_HASH=%%H"
		)
	)
) else (
	if "%MODE%"=="NORMAL" (
		call :log_error "No se puede calcular SHA256: archivo no existe en %IMG%"
		goto :fatal
	)
)

echo [+] Imagen local: %IMG%
echo [+] Tamano: !IMG_SIZE! bytes
if defined IMG_HASH (
	echo [+] SHA256: !IMG_HASH!
	>>"%LOG%" echo [INFO] %DATE% %TIME% - Imagen valida. Tamano=!IMG_SIZE! SHA256=!IMG_HASH!
) else (
	echo [!] Aviso: no se pudo calcular SHA256.
	>>"%LOG%" echo [WARN] %DATE% %TIME% - No se pudo calcular SHA256
)

call :run "Reiniciando a bootloader" adb reboot bootloader || goto :fatal
timeout /t 5 >nul

call :wait_fastboot || goto :fatal

echo [+] Obteniendo current-slot...
>>"%LOG%" echo.
>>"%LOG%" echo ==== %DATE% %TIME% - Obteniendo current-slot ====
set "CURRENT_SLOT_SEEN=0"
for /f "delims=" %%L in ('fastboot getvar current-slot 2^>^&1') do (
	echo %%L
	>>"%LOG%" echo %%L
	set "CURRENT_SLOT_SEEN=1"
)
if "%CURRENT_SLOT_SEEN%"=="0" (
	call :log_error "No se pudo leer current-slot"
	goto :fatal
)

call :run "Flasheando boot_a" fastboot flash boot_a "%IMG%" || goto :fatal
call :run "Flasheando boot_b" fastboot flash boot_b "%IMG%" || goto :fatal
call :run "Reiniciando dispositivo" fastboot reboot || goto :fatal

echo.
if "%MODE%"=="SIMULATOR" (
	echo [SIM] ===== SIMULACION COMPLETADA =====
	echo [SIM] Los cambios NO fueron aplicados
) else (
	echo [+] ROOT INSTALADO
)
echo [+] Redmi 12C
echo [+] Log: %LOG%
if "%DEBUG%"=="1" echo [+] Modo debug activo: comando usado con --debug

:menu_final
echo.
echo [?] ¿Qué deseas hacer?
echo.
echo   1 - Ver archivo log completo
echo   2 - Ver resumen (últimas 30 líneas)
echo   3 - Salir directamente
echo.
choice /c 123 /n /m "[?] Elige una opción [1/2/3]: "
if errorlevel 3 goto :exit_clean
if errorlevel 2 goto :show_summary
if errorlevel 1 goto :show_full_log

:show_full_log
cls
powershell -NoProfile -Command "Get-Content -Path '%LOG%'"
pause
goto :exit_clean

:show_summary
cls
echo ===== RESUMEN - Últimas 30 líneas del log =====
echo.
powershell -NoProfile -Command "if (Test-Path '%LOG%') { Get-Content -Path '%LOG%' -Tail 30 }"
echo.
pause
goto :exit_clean

:exit_clean
exit /b 0

:: Subroutines begin here
:init_log
>"%LOG%" echo ===== EasyRoot - Inicio: %DATE% %TIME% =====
>>"%LOG%" echo Script: %~f0
if "%DEBUG%"=="1" (
	echo [DBG] Modo debug activo.
	>>"%LOG%" echo [DBG] Modo debug activo.
)
if "%MODE%"=="SIMULATOR" (
	echo [SIM] Modo simulador activo.
	>>"%LOG%" echo [SIM] Modo simulador activo.
)
>>"%LOG%" echo [INFO] %DATE% %TIME% - Modo: %MODE%
exit /b 0

:show_mode_menu
if "%MODE%"=="NORMAL" (
	echo.
	echo ===== EASYROOT - Menu de Modo =====
	echo.
	echo   1 - Ejecucion Normal (instalacion real)
	echo   2 - Simulador (verificar sin aplicar cambios)
	echo.
	choice /c 12 /n /m "[?] Elige modo [1/2]: "
	if errorlevel 2 (
		set "MODE=SIMULATOR"
		echo.
		echo [SIM] Modo simulador activado
		echo [SIM] El script mostrara lo que haria sin aplicar cambios
		echo.
	) else (
		set "MODE=NORMAL"
		echo.
		echo [!] Modo normal: se aplicaran los cambios
		echo.
	)
	>>"%LOG%" echo [INFO] %DATE% %TIME% - Modo seleccionado: %MODE%
)
exit /b 0

:check_tool
where /q %~1
if errorlevel 1 (
	call :log_error "No se encontro %~1 en PATH"
	exit /b 1
)
if "%DEBUG%"=="1" echo [DBG] Herramienta detectada: %~1
>>"%LOG%" echo [INFO] %DATE% %TIME% - Herramienta detectada: %~1
exit /b 0

:check_adb_device
set "ADB_STATE="
for /f %%S in ('adb get-state 2^>nul') do set "ADB_STATE=%%S"
if /I not "!ADB_STATE!"=="device" (
	call :log_error "No hay dispositivo ADB en estado 'device'. Revisa cable, depuracion USB y autorizacion"
	adb devices >>"%LOG%" 2>&1
	exit /b 1
)
echo [+] Dispositivo ADB detectado.
>>"%LOG%" echo [INFO] %DATE% %TIME% - Dispositivo ADB detectado
exit /b 0

:wait_fastboot
echo [+] Esperando fastboot...
set /a i=0
:wait_loop
set "FB_DEV="
for /f "tokens=1" %%D in ('fastboot devices 2^>nul') do set "FB_DEV=%%D"
if defined FB_DEV (
	echo [+] Dispositivo fastboot detectado: !FB_DEV!
	>>"%LOG%" echo [INFO] %DATE% %TIME% - Fastboot detectado: !FB_DEV!
	exit /b 0
)
set /a i+=1
if !i! geq %MAX_WAIT% (
	call :log_error "No se detecto fastboot en %MAX_WAIT% segundos"
	exit /b 1
)
if "%DEBUG%"=="1" echo [DBG] Espera fastboot... intento !i!/%MAX_WAIT%
timeout /t 1 >nul
goto :wait_loop

:run
set "STEP=%~1"
set "CMD=%~2"
call :append_arg "%~3"
call :append_arg "%~4"
call :append_arg "%~5"
call :append_arg "%~6"
call :append_arg "%~7"
call :append_arg "%~8"
call :append_arg "%~9"
echo [+] !STEP!...
>>"%LOG%" echo.
>>"%LOG%" echo ==== %DATE% %TIME% - !STEP! ====
>>"%LOG%" echo CMD: !CMD!
if "%DEBUG%"=="1" echo [DBG] CMD: !CMD!

if "%MODE%"=="SIMULATOR" (
	echo [SIM] Simulando: !CMD!
	>>"%LOG%" echo [SIM] Simulando: !CMD!
	set "RC=0"
) else (
	!CMD! >>"%LOG%" 2>&1
	set "RC=!ERRORLEVEL!"
)

if not "!RC!"=="0" (
	call :log_error "Fallo en paso: !STEP! (codigo !RC!)"
	if "%DEBUG%"=="1" call :print_log_tail
	exit /b !RC!
)

if "%DEBUG%"=="1" echo [DBG] OK: !STEP!
exit /b 0

:append_arg
if "%~1"=="" exit /b 0
set "CMD=%CMD% "%~1""
exit /b 0

:log_error
echo [!] ERROR: %~1
>>"%LOG%" echo [ERROR] %DATE% %TIME% - %~1
exit /b 0

:print_log_tail
echo.
echo [DBG] Ultimas lineas del log:
powershell -NoProfile -Command "if (Test-Path '%LOG%') { Get-Content -Path '%LOG%' -Tail 25 }"
echo.
exit /b 0

:fatal
echo [!] Proceso detenido. Revisa el log: %LOG%
if "%DEBUG%"=="1" call :print_log_tail
pause
exit /b 1
