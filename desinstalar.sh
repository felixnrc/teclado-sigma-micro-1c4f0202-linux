#!/bin/bash
# Desinstala el daemon de teclas multimedia del teclado SiGma Micro 1c4f:0202.
#   sudo bash desinstalar.sh
set -e
if [ "$EUID" -ne 0 ]; then echo "Ejecuta con sudo:  sudo bash desinstalar.sh"; exit 1; fi

echo "==> Deteniendo y deshabilitando el servicio..."
systemctl disable --now sigma-volumen.service 2>/dev/null || true

echo "==> Eliminando archivos..."
rm -f /etc/systemd/system/sigma-volumen.service
rm -f /usr/local/bin/sigma-volumen-daemon.py
rm -f /etc/udev/rules.d/99-sigma-keyboard.rules
rm -f /etc/udev/rules.d/99-sigma-keyboard-power.rules
rm -f /etc/udev/rules.d/99-sigma-keyboard-disable-multimedia.rules
rm -f /etc/modprobe.d/sigma-keyboard-quirk.conf
rm -f /etc/modules-load.d/uinput.conf

echo "==> Recargando systemd y udev..."
systemctl daemon-reload
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=usb

echo ""
echo "Desinstalación completa. Reconecta el teclado para volver al estado por defecto."
echo "NOTA: no se desinstalan python3-pyusb ni python3-evdev (quítalos con dnf si quieres)."
echo "NOTA: el argumento de arranque usbhid.quirks (si se añadió) se quita con:"
echo "  sudo grubby --update-kernel=ALL --remove-args=\"usbhid.quirks=0x1c4f:0x0202:0x0008\""
