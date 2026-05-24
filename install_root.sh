#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG="${SCRIPT_DIR}/root_install.log"
IMG="${HOME}/magisk_patched.img"
REMOTE_IMG="/sdcard/Download/magisk_patched.img"
MAX_WAIT=40
MIN_IMG_SIZE=16777216
DEBUG=0
MODE="NORMAL"
MODE_SPECIFIED=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
	case "$1" in
		--debug)
			DEBUG=1
			shift
			;;
		--simulator|--dry-run)
			MODE="SIMULATOR"
			MODE_SPECIFIED=1
			shift
			;;
		*)
			shift
			;;
	esac
done

# ==== Utility Functions ====

init_log() {
	{
		echo "===== EasyRoot - Inicio: $(date) ====="
		echo "Script: ${BASH_SOURCE[0]}"
		if [[ "$DEBUG" == "1" ]]; then
			echo "[DBG] Modo debug activo."
		fi
		if [[ "$MODE" == "SIMULATOR" ]]; then
			echo "[SIM] Modo simulador activo."
		fi
		echo "[INFO] $(date) - Modo: $MODE"
	} > "$LOG"
}

log_message() {
	echo "$1" | tee -a "$LOG"
}

log_error() {
	echo "[!] ERROR: $1" | tee -a "$LOG"
}

log_info() {
	echo "[+] $1" | tee -a "$LOG"
}

log_debug() {
	if [[ "$DEBUG" == "1" ]]; then
		echo "[DBG] $1" | tee -a "$LOG"
	fi
	echo "[DBG] $1" >> "$LOG"
}

show_mode_menu() {
	if [[ "$MODE_SPECIFIED" == "0" ]]; then
		echo
		echo "===== EASYROOT - Menu de Modo ====="
		echo
		echo "   1 - Ejecucion Normal (instalacion real)"
		echo "   2 - Simulador (verificar sin aplicar cambios)"
		echo
		read -p "[?] Elige modo [1/2]: " choice
		case "$choice" in
			2)
				MODE="SIMULATOR"
				echo
				echo "[SIM] Modo simulador activado"
				echo "[SIM] El script mostrara lo que haria sin aplicar cambios"
				echo
				;;
			*)
				MODE="NORMAL"
				echo
				echo "[!] Modo normal: se aplicaran los cambios"
				echo
				;;
		esac
		echo "[INFO] $(date) - Modo seleccionado: $MODE" >> "$LOG"
	fi
}

check_tool() {
	local tool=$1
	if ! command -v "$tool" &> /dev/null; then
		log_error "No se encontro $tool en PATH"
		return 1
	fi
	log_debug "Herramienta detectada: $tool"
	echo "[INFO] $(date) - Herramienta detectada: $tool" >> "$LOG"
	return 0
}

check_adb_device() {
	local adb_state
	adb_state=$(adb get-state 2>/dev/null || echo "unknown")
	if [[ "$adb_state" != "device" ]]; then
		log_error "No hay dispositivo ADB en estado 'device'. Revisa cable, depuracion USB y autorizacion"
		adb devices >> "$LOG" 2>&1
		return 1
	fi
	log_info "Dispositivo ADB detectado."
	echo "[INFO] $(date) - Dispositivo ADB detectado" >> "$LOG"
	return 0
}

wait_fastboot() {
	log_info "Esperando fastboot..."
	local i=0
	while [[ $i -lt $MAX_WAIT ]]; do
		if fastboot devices 2>/dev/null | grep -q "fastboot\|unknown"; then
			local fb_dev
			fb_dev=$(fastboot devices 2>/dev/null | head -1 | awk '{print $1}')
			log_info "Dispositivo fastboot detectado: $fb_dev"
			echo "[INFO] $(date) - Fastboot detectado: $fb_dev" >> "$LOG"
			return 0
		fi
		log_debug "Espera fastboot... intento $((i+1))/$MAX_WAIT"
		sleep 1
		((i++))
	done
	log_error "No se detecto fastboot en $MAX_WAIT segundos"
	return 1
}

run_command() {
	local step=$1
	shift
	local cmd=("$@")

	echo "[+] $step..."
	{
		echo
		echo "==== $(date) - $step ===="
		echo "CMD: ${cmd[*]}"
	} >> "$LOG"
	log_debug "CMD: ${cmd[*]}"

	if [[ "$MODE" == "SIMULATOR" ]]; then
		echo "[SIM] Simulando: ${cmd[*]}"
		echo "[SIM] Simulando: ${cmd[*]}" >> "$LOG"
		return 0
	else
		if ! "${cmd[@]}" >> "$LOG" 2>&1; then
			local rc=$?
			log_error "Fallo en paso: $step (codigo $rc)"
			if [[ "$DEBUG" == "1" ]]; then
				print_log_tail
			fi
			return $rc
		fi
	fi
	log_debug "OK: $step"
	return 0
}

print_log_tail() {
	echo
	echo "[DBG] Ultimas lineas del log:"
	tail -25 "$LOG" 2>/dev/null || true
	echo
}

show_menu_final() {
	echo
	echo "[?] ¿Qué deseas hacer?"
	echo
	echo "   1 - Ver archivo log completo"
	echo "   2 - Ver resumen (últimas 30 líneas)"
	echo "   3 - Salir directamente"
	echo
	read -p "[?] Elige una opción [1/2/3]: " choice
	case "$choice" in
		1)
			show_full_log
			;;
		2)
			show_summary
			;;
		3)
			exit_clean
			;;
		*)
			exit_clean
			;;
	esac
}

show_full_log() {
	clear
	if [[ -f "$LOG" ]]; then
		cat "$LOG"
	fi
	read -p "Presiona Enter para continuar..."
	exit_clean
}

show_summary() {
	clear
	echo "===== RESUMEN - Últimas 30 líneas del log ====="
	echo
	if [[ -f "$LOG" ]]; then
		tail -30 "$LOG"
	fi
	echo
	read -p "Presiona Enter para continuar..."
	exit_clean
}

exit_clean() {
	exit 0
}

# ==== Main Script ====

main() {
	init_log

	if [[ "$MODE_SPECIFIED" == "0" ]]; then
		show_mode_menu
	fi

	check_tool adb || fatal
	check_tool fastboot || fatal
	check_adb_device || fatal

	log_info "Verificando imagen remota..."
	if ! adb shell ls "$REMOTE_IMG" >> "$LOG" 2>&1; then
		fatal
	fi

	echo "[*] Se flasheara boot_a y boot_b con $IMG"
	read -p "[?] Continuar? [S/N]: " confirm
	if [[ "$confirm" != "S" && "$confirm" != "s" ]]; then
		echo "[!] Operacion cancelada por el usuario."
		echo "[INFO] $(date) - Operacion cancelada por el usuario" >> "$LOG"
		read -p "Presiona Enter para salir..."
		exit 0
	fi

	run_command "Extrayendo imagen desde el telefono" adb pull "$REMOTE_IMG" "$IMG" || fatal

	if [[ "$MODE" == "NORMAL" ]]; then
		if [[ ! -f "$IMG" ]]; then
			log_error "La imagen no se guardo en $IMG"
			fatal
		fi
	else
		if [[ ! -f "$IMG" ]]; then
			echo "[SIM] Nota: Archivo no existe en simulador (esto es normal)"
			echo "[SIM] Nota: Archivo no existe en simulador" >> "$LOG"
		fi
	fi

	# Check image size
	if [[ -f "$IMG" ]]; then
		IMG_SIZE=$(stat -f%z "$IMG" 2>/dev/null || stat -c%s "$IMG" 2>/dev/null || echo "0")
		if [[ $IMG_SIZE -lt $MIN_IMG_SIZE ]]; then
			if [[ "$MODE" == "NORMAL" ]]; then
				log_error "Tamano de imagen sospechoso ($IMG_SIZE bytes). Verifica que magisk_patched.img sea correcto"
				fatal
			fi
		fi
	else
		if [[ "$MODE" == "NORMAL" ]]; then
			log_error "No se puede calcular SHA256: archivo no existe en $IMG"
			fatal
		fi
	fi

	# Calculate SHA256
	IMG_HASH=""
	if [[ -f "$IMG" ]]; then
		if command -v sha256sum &> /dev/null; then
			IMG_HASH=$(sha256sum "$IMG" | awk '{print $1}')
		elif command -v shasum &> /dev/null; then
			IMG_HASH=$(shasum -a 256 "$IMG" | awk '{print $1}')
		fi
	else
		if [[ "$MODE" == "NORMAL" ]]; then
			log_error "No se puede calcular SHA256: archivo no existe en $IMG"
			fatal
		fi
	fi

	log_info "Imagen local: $IMG"
	log_info "Tamano: $IMG_SIZE bytes"
	if [[ -n "$IMG_HASH" ]]; then
		log_info "SHA256: $IMG_HASH"
		echo "[INFO] $(date) - Imagen valida. Tamano=$IMG_SIZE SHA256=$IMG_HASH" >> "$LOG"
	else
		echo "[!] Aviso: no se pudo calcular SHA256."
		echo "[WARN] $(date) - No se pudo calcular SHA256" >> "$LOG"
	fi

	run_command "Reiniciando a bootloader" adb reboot bootloader || fatal
	sleep 5

	wait_fastboot || fatal

	log_info "Obteniendo current-slot..."
	echo >> "$LOG"
	echo "==== $(date) - Obteniendo current-slot ====" >> "$LOG"

	fastboot getvar current-slot 2>&1 | tee -a "$LOG"

	run_command "Flasheando boot_a" fastboot flash boot_a "$IMG" || fatal
	run_command "Flasheando boot_b" fastboot flash boot_b "$IMG" || fatal
	run_command "Reiniciando dispositivo" fastboot reboot || fatal

	echo
	if [[ "$MODE" == "SIMULATOR" ]]; then
		echo "[SIM] ===== SIMULACION COMPLETADA ====="
		echo "[SIM] Los cambios NO fueron aplicados"
	else
		echo "[+] ROOT INSTALADO"
	fi
	echo "[+] Redmi 12C"
	echo "[+] Log: $LOG"
	if [[ "$DEBUG" == "1" ]]; then
		echo "[+] Modo debug activo: comando usado con --debug"
	fi

	show_menu_final
}

fatal() {
	echo "[!] Proceso detenido. Revisa el log: $LOG"
	if [[ "$DEBUG" == "1" ]]; then
		print_log_tail
	fi
	read -p "Presiona Enter para salir..."
	exit 1
}

# Run main function
main
