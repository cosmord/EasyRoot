# EasyRoot

Script por lotes para extraer una imagen parcheada con Magisk desde un dispositivo Android, reiniciar a fastboot y flashear `boot_a` y `boot_b`.

Diseñado para facilitar el proceso de rooteo en dispositivos con esquema A/B, como el Xiaomi Redmi 12C NFC. El script automatiza los pasos necesarios para instalar Magisk sin necesidad de usar herramientas adicionales en PC.

## Requisitos

- `adb` y `fastboot` instalados y disponibles en `PATH`.
- Depuración USB activada en el teléfono.
- El dispositivo debe estar autorizado en ADB.
- La imagen `magisk_patched.img` debe existir en `/sdcard/Download/`.

## Uso

Ejecuta el script desde la misma carpeta del proyecto:

```bat
install_root.bat
```

Modo debug, con salida más detallada en terminal y log:

```bat
install_root.bat --debug
```

## Qué hace

1. Verifica que `adb` y `fastboot` existan.
2. Comprueba que el teléfono esté conectado por ADB.
3. Verifica que exista la imagen remota.
4. Copia `magisk_patched.img` al PC.
5. Calcula el hash SHA-256 de la imagen local.
6. Reinicia el dispositivo a bootloader.
7. Espera a que aparezca `fastboot`.
8. Muestra el `current-slot`.
9. Flashea `boot_a` y `boot_b`.
10. Reinicia el dispositivo.

## Seguridad

- El script pide confirmación antes de flashear.
- Si falta una herramienta, si el dispositivo no responde o si la imagen es sospechosa, el proceso se detiene.
- El log se guarda como `root_install.log` en la misma carpeta del script.

## Notas

- Este flujo está pensado para dispositivos con esquema A/B. En concreto, está diseñado para el Xiaomi Redmi 12C NFC. Puede no funcionar en otros modelos o marcas, revisar compatibilidad antes de usar.
- Asegúrate de que la imagen parcheada corresponda exactamente al firmware instalado en tu teléfono.
- Flashear imágenes incorrectas puede dejar el dispositivo sin arrancar.
