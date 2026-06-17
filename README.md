# Teclado SiGma Micro `1c4f:0202` en Linux — arreglo completo

🌐 **[Read this in English →](README.en.md)**

Solución para los teclados USB **SiGma Micro "Usb KeyBoard"** (ID de hardware
`1c4f:0202`, vendidos con marcas genéricas como *Soul*, *Necnon*, etc.) cuyas
**teclas multimedia no funcionan** en Linux y que, en algunos casos, **se
desconectan solos**.

> **English TL;DR:** Cheap SiGma Micro `1c4f:0202` keyboards ship a *corrupt HID
> report descriptor* on their second (multimedia) USB interface, so the Linux
> kernel can't parse it and the volume / media / calculator keys do nothing
> (and the device may disconnect). This repo disables USB autosuspend, frees
> that broken interface from `usbhid`, and runs a tiny user-space daemon that
> reads the raw HID reports with libusb and re-injects the keys via `uinput`.
> One command: `sudo bash instalar_daemon.sh`.

---

## Síntomas

- Las **letras y teclas normales escriben bien**.
- Las **teclas multimedia no hacen nada**: subir/bajar volumen, silenciar,
  play/pausa, calculadora, explorador de archivos, navegador, etc.
- En algunos equipos, el teclado **se desconecta solo** y hay que reconectar el
  cable USB.
- En `dmesg`/`journalctl -k` aparecen errores como:

  ```
  hid-generic 0003:1C4F:0202.000A: unknown main item tag 0x0
  hid-generic 0003:1C4F:0202.000A: unbalanced collection at end of report description
  hid-generic 0003:1C4F:0202.000A: probe with driver hid-generic failed with error -22
  ```

## Diagnóstico técnico

El teclado expone **dos interfaces HID**:

| Interfaz | Función | Estado |
|---|---|---|
| **0** (`3-1:1.0`) | Teclado principal (letras, modificadores) | ✅ Funciona |
| **1** (`3-1:1.1`) | Teclas multimedia (Consumer Control) | ❌ Descriptor HID corrupto de fábrica |

El descriptor de reporte de la interfaz 1 está **mal formado** (`unbalanced
collection`, `unknown main item tag 0x0`). El kernel no puede parsearlo y
descarta la interfaz con error `-22`, por lo que `usbhid` **no genera eventos**
para las teclas multimedia. Aun así `usbhid` queda enlazado y la sigue
sondeando, lo que en algunos modelos provoca **desconexiones** del dispositivo
completo al pulsar esas teclas.

> ⚠️ **No se puede arreglar con `usbhid.quirks`.** Ningún *quirk* repara un
> descriptor mal formado. (Nota: el valor `HID_QUIRK_NOGET` real es `0x0008`,
> no `0x0020` — ese último es `HID_QUIRK_BADPAD` y no sirve aquí.)

### Lo que envía realmente el hardware

A pesar del descriptor roto, los **reportes crudos sí son válidos**: 3 bytes con
el formato `[ReportID=01][código Consumer low][high]`. Capturados con
`usbhid-dump`:

| Tecla | Reporte | Código Consumer |
|---|---|---|
| Subir volumen | `01 E9 00` | `0xE9` |
| Bajar volumen | `01 EA 00` | `0xEA` |
| Silenciar (mute) | `01 E2 00` | `0xE2` |
| Play / Pausa | `01 CD 00` | `0xCD` |
| Calculadora | `01 92 01` | `0x192` |
| Explorador de archivos | `01 94 01` | `0x194` |

> 💡 Fíjate que la calculadora y el explorador usan **2 bytes** (`0x192`,
> `0x194`); el volumen usa solo el byte bajo.

## La solución

En lugar de pelear con el kernel, un **daemon en espacio de usuario**:

1. **Desactiva el autosuspend** del teclado (regla `udev`) para evitar
   desconexiones por ahorro de energía.
2. **Libera la interfaz 1 de `usbhid`** (regla `udev`) para que el kernel deje
   de sondear el descriptor roto.
3. **Reclama esa interfaz con `libusb`** (PyUSB), lee los reportes crudos y los
   **reinyecta como un teclado virtual** vía `uinput` (python-evdev).

Resultado: el teclado principal sigue intacto y las teclas multimedia funcionan
en todo el sistema, sin recompilar nada al actualizar el kernel.

```
┌─────────────────┐   USB    ┌──────────────────────────────────────┐
│ Teclado 1c4f:    │  iface 0 │ usbhid  → teclado normal (letras)     │
│ 0202             │──────────┤                                       │
│                  │  iface 1 │ (usbhid liberado por udev)            │
└─────────────────┘          │      ↓ libusb (PyUSB)                 │
                              │  volumen_daemon.py                    │
                              │      ↓ uinput (evdev)                 │
                              │  Teclado virtual → eventos multimedia │
                              └──────────────────────────────────────┘
```

## Requisitos

- Linux con `systemd` y `udev` (probado en **Fedora 44**, kernel 7.0).
- `python3` con **PyUSB** y **python-evdev** (los instala el script).
- El módulo `uinput` (el script lo carga y lo deja persistente).

El instalador detecta tu distribución e instala los paquetes correctos:

| Distribución | Gestor | Paquetes |
|---|---|---|
| Fedora / RHEL | `dnf` | `python3-pyusb` `python3-evdev` |
| Debian / Ubuntu | `apt` | `python3-usb` `python3-evdev` |
| Arch / Manjaro | `pacman` | `python-pyusb` `python-evdev` |
| openSUSE | `zypper` | `python3-pyusb` `python3-evdev` |
| Otras | — | `pip install pyusb evdev` |

## Instalación (recomendada — con teclas multimedia)

```bash
git clone https://github.com/felixnrc/teclado-sigma-micro-1c4f0202-linux.git
cd teclado-sigma-micro-1c4f0202-linux
sudo bash instalar_daemon.sh
```

Después **desconecta y reconecta el cable USB** del teclado y prueba las teclas
multimedia.

El instalador:
- Instala PyUSB y python-evdev con el gestor de tu distro (ver tabla arriba).
- Carga el módulo `uinput` al arranque.
- Copia el daemon a `/usr/local/bin/sigma-volumen-daemon.py`.
- Escribe las reglas `udev` en `/etc/udev/rules.d/99-sigma-keyboard.rules`.
- Crea y activa el servicio `sigma-volumen.service`.

## Verificación

```bash
systemctl status sigma-volumen.service        # debe estar active (running)
journalctl -u sigma-volumen.service -f         # ver eventos en vivo
```

Al arrancar deberías ver `Teclado multimedia conectado. Escuchando teclas...`.

## Personalizar / añadir teclas

Si alguna tecla multimedia no responde, el daemon registra su código:

```
[sigma-volumen] Código consumer sin mapear: 0x01A4  (reporte: 01 A4 01)
```

Añade ese código a `KEYMAP` en `volumen_daemon.py` (lista de teclas en
`/usr/include/linux/input-event-codes.h` o `python3 -c "from evdev import ecodes; print([k for k in dir(ecodes) if k.startswith('KEY_')])"`), por ejemplo:

```python
0x1A4: e.KEY_PROG1,
```

Luego aplica el cambio:

```bash
sudo bash actualizar_daemon.sh
```

## Solución de problemas

| Síntoma | Causa / arreglo |
|---|---|
| `No such device` en bucle | La interfaz 1 quedó `authorized=0`. Reconecta el cable USB, o `sudo sh -c 'echo 1 > /sys/bus/usb/devices/3-*:1.1/authorized'`. |
| Las letras tampoco funcionan | La interfaz 0 debería seguir en `usbhid`. Revisa `cat /sys/bus/usb/devices/3-*:1.0/authorized` (debe ser `1`). |
| Una tecla no responde | Mira los logs por `Código consumer sin mapear` y añádelo a `KEYMAP`. |
| Sigue desconectándose | Confirma que la regla de autosuspend está aplicada: `cat /sys/bus/usb/devices/3-*/power/control` debe decir `on`. |

## Desinstalación

```bash
sudo bash desinstalar.sh
```

## Alternativa: solo estabilidad (sin teclas multimedia)

Si no te interesan las teclas multimedia y solo quieres que el teclado **deje de
desconectarse**, `aplicar_parche.sh` desactiva el autosuspend y **deshabilita**
la interfaz multimedia rota (no la usa, solo evita que moleste):

```bash
sudo bash aplicar_parche.sh
```

## Contenido del repositorio

| Archivo | Descripción |
|---|---|
| `instalar_daemon.sh` | Instalador completo (opción recomendada). |
| `volumen_daemon.py` | El daemon que lee la interfaz multimedia y emite las teclas. |
| `actualizar_daemon.sh` | Reinstala el daemon y reinicia el servicio tras editarlo. |
| `desinstalar.sh` | Elimina daemon, servicio y reglas udev. |
| `capturar_multimedia.sh` | Herramienta de diagnóstico: captura los reportes HID crudos. |
| `aplicar_parche.sh` | Alternativa "solo estabilidad" (sin multimedia). |
| `log_teclado.txt` | Log de kernel del diagnóstico original. |

## Aviso

Probado en un teclado **`1c4f:0202`** concreto. Otros modelos SiGma Micro pueden
enviar **códigos distintos**; usa `capturar_multimedia.sh` para ver los tuyos y
ajusta `KEYMAP`. Si tu teclado funciona con códigos diferentes, ¡un *pull
request* con la tabla ayuda a otros!

## Licencia

[MIT](LICENSE).
