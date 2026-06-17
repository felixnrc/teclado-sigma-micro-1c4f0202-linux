# SiGma Micro `1c4f:0202` keyboard on Linux — complete fix

🌐 **[Leer en español →](README.md)**

Fix for the **SiGma Micro "Usb KeyBoard"** USB keyboards (hardware ID
`1c4f:0202`, sold under generic brands such as *Soul*, *Necnon*, etc.) whose
**multimedia keys don't work** on Linux and which, in some cases, **disconnect
on their own**.

> **TL;DR:** These cheap SiGma Micro `1c4f:0202` keyboards ship a *corrupt HID
> report descriptor* on their second (multimedia) USB interface, so the Linux
> kernel can't parse it and the volume / media / calculator keys do nothing
> (and the device may disconnect). This repo disables USB autosuspend, frees
> that broken interface from `usbhid`, and runs a tiny user-space daemon that
> reads the raw HID reports with libusb and re-injects the keys via `uinput`.
> One command: `sudo bash instalar_daemon.sh`.

---

## Symptoms

- **Letters and normal keys type fine.**
- **Multimedia keys do nothing:** volume up/down, mute, play/pause,
  calculator, file browser, web browser, etc.
- On some machines the keyboard **disconnects by itself** and you have to
  unplug/replug the USB cable.
- `dmesg` / `journalctl -k` shows errors like:

  ```
  hid-generic 0003:1C4F:0202.000A: unknown main item tag 0x0
  hid-generic 0003:1C4F:0202.000A: unbalanced collection at end of report description
  hid-generic 0003:1C4F:0202.000A: probe with driver hid-generic failed with error -22
  ```

## Technical diagnosis

The keyboard exposes **two HID interfaces**:

| Interface | Role | Status |
|---|---|---|
| **0** (`3-1:1.0`) | Main keyboard (letters, modifiers) | ✅ Works |
| **1** (`3-1:1.1`) | Multimedia keys (Consumer Control) | ❌ Corrupt HID descriptor |

Interface 1's report descriptor is **malformed** (`unbalanced collection`,
`unknown main item tag 0x0`). The kernel can't parse it and drops the interface
with error `-22`, so `usbhid` **emits no events** for the multimedia keys. Worse,
`usbhid` stays bound and keeps polling it, which on some models causes the whole
device to **disconnect** when those keys are pressed.

> ⚠️ **This can't be fixed with `usbhid.quirks`.** No quirk repairs a malformed
> descriptor. (Note: the real `HID_QUIRK_NOGET` value is `0x0008`, not `0x0020`
> — the latter is `HID_QUIRK_BADPAD` and is useless here.)

### What the hardware actually sends

Despite the broken descriptor, the **raw reports are valid**: 3 bytes formatted
as `[ReportID=01][Consumer code low][high]`. Captured with `usbhid-dump`:

| Key | Report | Consumer code |
|---|---|---|
| Volume up | `01 E9 00` | `0xE9` |
| Volume down | `01 EA 00` | `0xEA` |
| Mute | `01 E2 00` | `0xE2` |
| Play / Pause | `01 CD 00` | `0xCD` |
| Calculator | `01 92 01` | `0x192` |
| File browser | `01 94 01` | `0x194` |

> 💡 Note that calculator and file browser use **2 bytes** (`0x192`, `0x194`);
> volume uses only the low byte.

## The solution

Instead of fighting the kernel, a **user-space daemon**:

1. **Disables autosuspend** for the keyboard (a `udev` rule) to prevent
   power-saving disconnects.
2. **Frees interface 1 from `usbhid`** (a `udev` rule) so the kernel stops
   polling the broken descriptor.
3. **Claims that interface with `libusb`** (PyUSB), reads the raw reports, and
   **re-injects them as a virtual keyboard** via `uinput` (python-evdev).

Result: the main keyboard stays untouched and the multimedia keys work
system-wide, with nothing to recompile on kernel updates.

```
┌─────────────────┐   USB    ┌──────────────────────────────────────┐
│ Keyboard 1c4f:   │  iface 0 │ usbhid  → normal keyboard (letters)   │
│ 0202             │──────────┤                                       │
│                  │  iface 1 │ (usbhid freed by udev)                │
└─────────────────┘          │      ↓ libusb (PyUSB)                 │
                              │  volumen_daemon.py                    │
                              │      ↓ uinput (evdev)                 │
                              │  Virtual keyboard → multimedia events │
                              └──────────────────────────────────────┘
```

## Requirements

- Linux with `systemd` and `udev` (tested on **Fedora 44**, kernel 7.0).
- `python3` with **PyUSB** and **python-evdev** (installed by the script).
- The `uinput` module (the script loads it and makes it persistent).

The installer detects your distribution and installs the right packages:

| Distribution | Manager | Packages |
|---|---|---|
| Fedora / RHEL | `dnf` | `python3-pyusb` `python3-evdev` |
| Debian / Ubuntu | `apt` | `python3-usb` `python3-evdev` |
| Arch / Manjaro | `pacman` | `python-pyusb` `python-evdev` |
| openSUSE | `zypper` | `python3-pyusb` `python3-evdev` |
| Other | — | `pip install pyusb evdev` |

## Installation (recommended — with multimedia keys)

```bash
git clone https://github.com/felixnrc/teclado-sigma-micro-1c4f0202-linux.git
cd teclado-sigma-micro-1c4f0202-linux
sudo bash instalar_daemon.sh
```

Then **unplug and replug the keyboard's USB cable** and try the multimedia keys.

The installer:
- Installs PyUSB and python-evdev with your distro's package manager (see table).
- Loads the `uinput` module at boot.
- Copies the daemon to `/usr/local/bin/sigma-volumen-daemon.py`.
- Writes the `udev` rules to `/etc/udev/rules.d/99-sigma-keyboard.rules`.
- Creates and enables the `sigma-volumen.service` systemd unit.

### Manual install per distro

If you prefer to install dependencies yourself before running the script:

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y python3-usb python3-evdev

# Arch / Manjaro
sudo pacman -Sy --needed python-pyusb python-evdev

# Fedora / RHEL
sudo dnf install -y python3-pyusb python3-evdev
```

Then run `sudo bash instalar_daemon.sh` (it will detect the deps are present).

## Verification

```bash
systemctl status sigma-volumen.service        # should be active (running)
journalctl -u sigma-volumen.service -f         # watch events live
```

On startup you should see `Teclado multimedia conectado. Escuchando teclas...`.

## Customize / add keys

If a multimedia key doesn't respond, the daemon logs its code:

```
[sigma-volumen] Código consumer sin mapear: 0x01A4  (reporte: 01 A4 01)
```

Add that code to `KEYMAP` in `volumen_daemon.py` (key names in
`/usr/include/linux/input-event-codes.h` or
`python3 -c "from evdev import ecodes; print([k for k in dir(ecodes) if k.startswith('KEY_')])"`),
for example:

```python
0x1A4: e.KEY_PROG1,
```

Then apply the change:

```bash
sudo bash actualizar_daemon.sh
```

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `No such device` in a loop | Interface 1 ended up `authorized=0`. Replug the USB cable, or `sudo sh -c 'echo 1 > /sys/bus/usb/devices/3-*:1.1/authorized'`. |
| Letters don't work either | Interface 0 should stay on `usbhid`. Check `cat /sys/bus/usb/devices/3-*:1.0/authorized` (must be `1`). |
| One key doesn't respond | Look for `Código consumer sin mapear` in the logs and add it to `KEYMAP`. |
| Still disconnecting | Confirm the autosuspend rule applied: `cat /sys/bus/usb/devices/3-*/power/control` must say `on`. |

## Uninstall

```bash
sudo bash desinstalar.sh
```

## Alternative: stability only (no multimedia keys)

If you don't care about multimedia keys and only want the keyboard to **stop
disconnecting**, `aplicar_parche.sh` disables autosuspend and **disables** the
broken multimedia interface (it won't be used, just kept out of the way):

```bash
sudo bash aplicar_parche.sh
```

## Repository contents

| File | Description |
|---|---|
| `instalar_daemon.sh` | Full installer (recommended). |
| `volumen_daemon.py` | The daemon that reads the multimedia interface and emits the keys. |
| `actualizar_daemon.sh` | Reinstalls the daemon and restarts the service after editing it. |
| `desinstalar.sh` | Removes daemon, service and udev rules. |
| `capturar_multimedia.sh` | Diagnostic tool: captures the raw HID reports. |
| `aplicar_parche.sh` | "Stability only" alternative (no multimedia). |
| `log_teclado.txt` | Kernel log from the original diagnosis. |

## Disclaimer

Tested on one specific **`1c4f:0202`** keyboard. Other SiGma Micro models may
send **different codes**; use `capturar_multimedia.sh` to see yours and adjust
`KEYMAP`. If your keyboard works with different codes, a pull request with the
table helps others!

## License

[MIT](LICENSE).
