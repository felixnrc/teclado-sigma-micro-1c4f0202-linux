#!/usr/bin/env python3
"""
Daemon de teclas multimedia para el teclado SiGma Micro (1c4f:0202).

La interfaz 1 del teclado tiene un descriptor HID corrupto que el kernel no
puede parsear, así que usbhid no genera eventos de teclado para las teclas
multimedia. Este daemon reclama esa interfaz con libusb, lee los reportes
crudos (3 bytes: [reportID=01][código consumer][00]) y reinyecta las teclas
como un teclado virtual vía uinput.

Códigos capturados del hardware (HID Consumer Page 0x0C):
    0xE9 -> Subir volumen      0xEA -> Bajar volumen     0xE2 -> Silenciar
"""
import sys
import time

import usb.core
import usb.util
from evdev import UInput, ecodes as e

VID, PID = 0x1C4F, 0x0202
IFACE = 1  # interfaz multimedia (descriptor roto)

# Mapeo código HID Consumer -> tecla de Linux.
# Volumen confirmado por captura; el resto son códigos Consumer estándar por si
# este modelo emite también play/pausa, siguiente, etc.
KEYMAP = {
    0xE9: e.KEY_VOLUMEUP,
    0xEA: e.KEY_VOLUMEDOWN,
    0xE2: e.KEY_MUTE,
    0xCD: e.KEY_PLAYPAUSE,
    0xB5: e.KEY_NEXTSONG,
    0xB6: e.KEY_PREVIOUSSONG,
    0xB7: e.KEY_STOPCD,
    0xB3: e.KEY_FASTFORWARD,
    0xB4: e.KEY_REWIND,
    0x192: e.KEY_CALC,         # calculadora
    0x194: e.KEY_FILE,         # explorador de archivos / "Mi PC"
    0x196: e.KEY_WWW,          # navegador
    0x18A: e.KEY_MAIL,         # correo
    0x223: e.KEY_HOMEPAGE,     # AC Home
    0x221: e.KEY_SEARCH,       # AC Search
    0x224: e.KEY_BACK,         # AC Back
    0x225: e.KEY_FORWARD,      # AC Forward
    0x226: e.KEY_STOP,         # AC Stop
    0x227: e.KEY_REFRESH,      # AC Refresh
    0x22A: e.KEY_BOOKMARKS,    # AC Bookmarks
    0x183: e.KEY_CONFIG,       # configuración/media player
}


def log(msg):
    print(f"[sigma-volumen] {msg}", flush=True)


def open_device():
    """Localiza el teclado, libera usbhid de la interfaz 1 y devuelve (dev, ep)."""
    dev = usb.core.find(idVendor=VID, idProduct=PID)
    if dev is None:
        return None

    # Soltar usbhid de la interfaz 1 si sigue enganchado (evita conflicto/crash).
    try:
        if dev.is_kernel_driver_active(IFACE):
            dev.detach_kernel_driver(IFACE)
    except (usb.core.USBError, NotImplementedError):
        pass

    usb.util.claim_interface(dev, IFACE)

    cfg = dev.get_active_configuration()
    intf = cfg[(IFACE, 0)]
    ep = usb.util.find_descriptor(
        intf,
        custom_match=lambda d: usb.util.endpoint_direction(d.bEndpointAddress)
        == usb.util.ENDPOINT_IN
        and usb.util.endpoint_type(d.bmAttributes) == usb.util.ENDPOINT_TYPE_INTR,
    )
    if ep is None:
        usb.util.dispose_resources(dev)
        return None
    return dev, ep


def main():
    ui = UInput(
        {e.EV_KEY: sorted(set(KEYMAP.values()))},
        name="SiGma Micro Multimedia (daemon)",
        vendor=VID,
        product=PID,
    )
    log("Teclado virtual de teclas multimedia creado.")
    current = None  # tecla actualmente "pulsada" (para soltar al recibir 0x00)

    while True:
        try:
            opened = open_device()
        except usb.core.USBError as ex:
            log(f"No se pudo abrir el dispositivo: {ex}")
            opened = None

        if not opened:
            time.sleep(2)
            continue

        dev, ep = opened
        log("Teclado multimedia conectado. Escuchando teclas...")

        while True:
            try:
                data = dev.read(ep.bEndpointAddress, ep.wMaxPacketSize, timeout=0)
            except usb.core.USBError as ex:
                # 110 = timeout (no debería con timeout=0); el resto = desconexión
                if getattr(ex, "errno", None) == 110:
                    continue
                log("Desconexión detectada, reintentando...")
                break

            # El código Consumer puede ocupar 2 bytes (low + high). Volumen usa
            # solo el byte bajo (high=0); calculadora, explorador, etc. usan los
            # dos bytes (p.ej. 0x192 = [01][92][01]).
            if len(data) > 2:
                code = data[1] | (data[2] << 8)
            elif len(data) > 1:
                code = data[1]
            else:
                code = 0

            if code == 0:
                if current is not None:
                    ui.write(e.EV_KEY, current, 0)
                    ui.syn()
                    current = None
                continue

            key = KEYMAP.get(code)
            if key is None:
                raw = " ".join(f"{b:02X}" for b in data)
                log(f"Código consumer sin mapear: 0x{code:04X}  (reporte: {raw})")
                continue

            # Si había otra tecla pulsada, soltarla antes de pulsar la nueva.
            if current is not None and current != key:
                ui.write(e.EV_KEY, current, 0)
                ui.syn()
            ui.write(e.EV_KEY, key, 1)
            ui.syn()
            current = key

        # Limpieza al desconectar
        if current is not None:
            ui.write(e.EV_KEY, current, 0)
            ui.syn()
            current = None
        try:
            usb.util.dispose_resources(dev)
        except usb.core.USBError:
            pass
        time.sleep(2)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
