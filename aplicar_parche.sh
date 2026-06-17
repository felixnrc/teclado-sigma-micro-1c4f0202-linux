#!/bin/bash
set -e

# =============================================================================
# OPCIÓN B: SOLO ESTABILIDAD (sin teclas multimedia).
# Este script desactiva el autosuspend y DESHABILITA la interfaz multimedia rota
# para que el teclado deje de desconectarse. Las teclas multimedia NO funcionarán.
#
# ¿Quieres que las teclas multimedia (volumen, etc.) funcionen?
#   ->  usa en su lugar:  sudo bash instalar_daemon.sh
# =============================================================================

echo "Aplicando parches para el teclado SiGma Micro (1c4f:0202)..."

# =============================================================================
# DIAGNÓSTICO REAL (jun 2026):
# El teclado expone DOS interfaces HID:
#   - Interfaz 0 (3-1:1.0) -> teclado principal. FUNCIONA (letras, teclas normales).
#   - Interfaz 1 (3-1:1.1) -> teclas multimedia. Tiene un descriptor de reporte HID
#     CORRUPTO de fábrica. El kernel falla al parsearlo:
#       "unknown main item tag 0x0"
#       "unbalanced collection at end of report description"
#       "probe ... failed with error -22"
#     Aun así usbhid queda enlazado a esa interfaz y la sigue sondeando, lo que
#     puede provocar desconexiones del dispositivo completo al pulsar esas teclas.
#
# Por eso la solución de verdad es DEAUTORIZAR solo la interfaz 1 (multimedia),
# dejando intacta la interfaz 0 (el teclado normal).
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Regla udev: desactivar autosuspend (evita desconexiones por ahorro de energía)
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee /etc/udev/rules.d/99-sigma-keyboard-power.rules > /dev/null
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1c4f", ATTR{idProduct}=="0202", ATTR{power/control}="on"
EOF

# -----------------------------------------------------------------------------
# 2. Regla udev: deautorizar SOLO la interfaz 1 (multimedia, descriptor roto)
#    -> el kernel deja de sondearla y no puede tumbar el teclado.
#       La interfaz 0 (teclado normal) sigue funcionando con normalidad.
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee /etc/udev/rules.d/99-sigma-keyboard-disable-multimedia.rules > /dev/null
ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", ATTRS{idVendor}=="1c4f", ATTRS{idProduct}=="0202", ATTR{bInterfaceNumber}=="01", ATTR{authorized}="0"
EOF

# -----------------------------------------------------------------------------
# 3. Quirk usbhid HID_QUIRK_NOGET (valor correcto = 0x0008).
#    NOTA: el script anterior usaba 0x0020, que en include/linux/hid.h es
#    HID_QUIRK_BADPAD (inútil para este teclado). El NOGET real es 0x0008.
#    Evita peticiones GET_REPORT que el firmware no responde bien durante el init.
# -----------------------------------------------------------------------------
cat <<EOF | sudo tee /etc/modprobe.d/sigma-keyboard-quirk.conf > /dev/null
options usbhid quirks=0x1c4f:0x0202:0x0008
EOF

# Si usbhid está compilado en el kernel (built-in), modprobe.d no aplica;
# se pasa como argumento de arranque con grubby:
if command -v grubby &> /dev/null; then
    # Quitar primero el valor antiguo erróneo (0x0020) si existe
    sudo grubby --update-kernel=ALL --remove-args="usbhid.quirks=0x1c4f:0x0202:0x0020" 2>/dev/null || true
    sudo grubby --update-kernel=ALL --args="usbhid.quirks=0x1c4f:0x0202:0x0008"
fi

# -----------------------------------------------------------------------------
# 4. Recargar y aplicar reglas udev en caliente (sin reiniciar)
# -----------------------------------------------------------------------------
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=usb

echo "=========================================================="
echo "Reglas aplicadas."
echo "El teclado normal (letras) sigue funcionando."
echo "La interfaz multimedia rota queda deshabilitada para que no"
echo "provoque desconexiones."
echo ""
echo "Si no se aplica en caliente, desconecta y reconecta el cable"
echo "USB del teclado, o reinicia para que tome el quirk de arranque."
echo "=========================================================="
