#!/bin/bash
# Instala el daemon de teclas multimedia para el teclado SiGma Micro 1c4f:0202.
#   sudo bash instalar_daemon.sh
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ejecuta con sudo:  sudo bash instalar_daemon.sh"
  exit 1
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DAEMON_SRC="$SRC_DIR/volumen_daemon.py"
DAEMON_DST="/usr/local/bin/sigma-volumen-daemon.py"

echo "==> 1/6 Instalando dependencias de Python (pyusb, evdev)..."
if command -v dnf &>/dev/null; then
  dnf install -y python3-pyusb python3-evdev
elif command -v apt-get &>/dev/null; then
  apt-get update && apt-get install -y python3-usb python3-evdev
elif command -v pacman &>/dev/null; then
  pacman -Sy --needed --noconfirm python-pyusb python-evdev
elif command -v zypper &>/dev/null; then
  zypper install -y python3-pyusb python3-evdev
else
  echo "No reconozco tu gestor de paquetes. Instala manualmente PyUSB y python-evdev"
  echo "y vuelve a ejecutar este script (puedes usar: pip install pyusb evdev)."
  exit 1
fi

echo "==> 2/6 Asegurando que el módulo uinput se cargue al arranque..."
modprobe uinput || true
echo uinput > /etc/modules-load.d/uinput.conf

echo "==> 3/6 Instalando el daemon en $DAEMON_DST ..."
install -m 0755 "$DAEMON_SRC" "$DAEMON_DST"

echo "==> 4/6 Escribiendo reglas udev..."
# Eliminar la regla antigua que apagaba la interfaz multimedia (ya no la queremos
# apagada: el daemon la va a usar).
rm -f /etc/udev/rules.d/99-sigma-keyboard-disable-multimedia.rules

cat > /etc/udev/rules.d/99-sigma-keyboard.rules <<'EOF'
# Teclado SiGma Micro 1c4f:0202

# Desactivar autosuspend (evita desconexiones por ahorro de energía)
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="1c4f", ATTR{idProduct}=="0202", ATTR{power/control}="on"

# Liberar usbhid de la interfaz 1 (multimedia, descriptor roto) para que no la
# sondee y la pueda reclamar el daemon de espacio de usuario.
ACTION=="bind", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_interface", DRIVER=="usbhid", ATTRS{idVendor}=="1c4f", ATTRS{idProduct}=="0202", ATTR{bInterfaceNumber}=="01", RUN+="/bin/sh -c 'echo %k > /sys/bus/usb/drivers/usbhid/unbind'"
EOF
# La antigua regla 99-sigma-keyboard-power.rules queda cubierta por la de arriba.
rm -f /etc/udev/rules.d/99-sigma-keyboard-power.rules

echo "==> 5/6 Instalando el servicio systemd..."
cat > /etc/systemd/system/sigma-volumen.service <<EOF
[Unit]
Description=Daemon de teclas multimedia para teclado SiGma Micro 1c4f:0202
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $DAEMON_DST
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

echo "==> 6/6 Recargando reglas y arrancando el servicio..."
udevadm control --reload-rules
udevadm trigger --action=add --subsystem-match=usb
systemctl daemon-reload
systemctl enable --now sigma-volumen.service

echo ""
echo "=========================================================="
echo "Instalación completa."
echo "Desconecta y reconecta el cable USB del teclado y prueba"
echo "las teclas de volumen."
echo ""
echo "Ver estado:   systemctl status sigma-volumen.service"
echo "Ver logs:     journalctl -u sigma-volumen.service -f"
echo "=========================================================="
