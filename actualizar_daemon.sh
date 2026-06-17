#!/bin/bash
# Actualiza el daemon instalado con la última versión y reinicia el servicio.
#   sudo bash actualizar_daemon.sh
set -e
if [ "$EUID" -ne 0 ]; then echo "Ejecuta con sudo."; exit 1; fi
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m 0755 "$SRC_DIR/volumen_daemon.py" /usr/local/bin/sigma-volumen-daemon.py
systemctl restart sigma-volumen.service
echo "Daemon actualizado y servicio reiniciado."
