#!/bin/bash
# Captura los reportes HID crudos que emite la interfaz multimedia (interfaz 1)
# del teclado SiGma Micro 1c4f:0202, para diseñar el daemon de volumen.
#
# Uso:  sudo bash capturar_multimedia.sh
# Durante los 12 segundos de captura, PULSA varias veces: Subir Volumen,
# Bajar Volumen y Silenciar (Mute). Cada pulsación imprimirá una línea de bytes.

set -e

VID=1c4f
PID=0202

# Localizar la interfaz 1 en sysfs
IFACE_PATH=""
for dev in /sys/bus/usb/devices/*; do
  if [ -f "$dev/idVendor" ] && [ "$(cat "$dev/idVendor" 2>/dev/null)" = "$VID" ] \
     && [ "$(cat "$dev/idProduct" 2>/dev/null)" = "$PID" ]; then
    for i in "$dev":*; do
      if [ "$(cat "$i/bInterfaceNumber" 2>/dev/null)" = "01" ]; then
        IFACE_PATH="$i"
      fi
    done
  fi
done

if [ -z "$IFACE_PATH" ]; then
  echo "ERROR: no se encontró el teclado $VID:$PID. ¿Está conectado?"
  exit 1
fi

echo "Interfaz multimedia: $(basename "$IFACE_PATH")"

# Re-autorizar temporalmente la interfaz para poder leerla
echo "Re-autorizando interfaz 1 temporalmente..."
echo 1 > "$IFACE_PATH/authorized"
# Quitar usbhid de esa interfaz para que no la sondee (evita crash); usbhid-dump
# también desacopla el driver, pero lo hacemos explícito por seguridad.
echo "$(basename "$IFACE_PATH")" > /sys/bus/usb/drivers/usbhid/unbind 2>/dev/null || true
sleep 1

echo ""
echo "================= DESCRIPTOR DE REPORTE (interfaz 1) ================="
usbhid-dump -d $VID:$PID -i 1 2>/dev/null || echo "(no se pudo leer el descriptor)"

echo ""
echo "============== AHORA PULSA LAS TECLAS DE VOLUMEN (12 s) =============="
echo ">>> Pulsa varias veces: SUBIR vol, BAJAR vol, MUTE <<<"
echo ""
timeout 12 usbhid-dump -d $VID:$PID -i 1 -es 2>/dev/null || true

echo ""
echo "================= FIN DE LA CAPTURA ================="
# Restaurar estado seguro: volver a deautorizar la interfaz 1
echo 0 > "$IFACE_PATH/authorized" 2>/dev/null || true
echo "Interfaz 1 deautorizada de nuevo (estado seguro restaurado)."
