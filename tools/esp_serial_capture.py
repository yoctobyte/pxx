#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reset an ESP32 through its serial port's RTS/DTR lines and capture what it
prints, from the boot ROM on, for N seconds.

    esp_serial_capture.py <port> <seconds> [--no-reset] [--until TOKEN]

Why this exists: tools/esp_flash.sh used to let esptool hard-reset the chip and
THEN open the tty with `cat`. On a chip whose console is the built-in
USB-Serial/JTAG (the ESP32-C3's /dev/ttyACM*), the reset makes the port
disappear and come back, so the first lines -- the boot banner and the
program's first output -- were gone before `cat` could reopen it. Measured
2026-09-27 on the first C3 board: hello-c3 printed i=2..5 of i=1..5. Here the
port is opened FIRST and the reset is issued through it, so nothing is missed.

The reset sequence is esptool's classic one (RTS asserted = EN low, DTR held
off so the chip boots from flash, not into download mode). If the port
vanishes during the reset, it is reopened for the rest of the window.

--no-reset skips that pulse, but it cannot stop a board whose USB-UART
bridge resets the chip when the port is OPENED: measured 2026-09-27 on an
ESP32-S3 devkit with a CH343, opening with --no-reset rebooted it once.

--until TOKEN stops as soon as TOKEN has been printed (the line holding it is
read to its end), with <seconds> as the upper bound: a soak ends on its own
completion token, not on a guessed duration.

The port is held EXCLUSIVELY for the whole capture: TIOCEXCL on the tty, so
any other non-root open() of it (esptool, a monitor, another capture) fails
with EBUSY before its driver touches DTR/RTS, plus pyserial's exclusive=True
flock for pyserial users that ask. 2026-09-27: a second seat's esptool-style
connect on the C3's /dev/ttyACM0 reset the board into download mode in the
middle of another seat's capture. A port that is already held makes this
script exit 3 with "busy" on stderr. The lock goes with the fd, so a port
that re-enumerates is locked again on the reopen.

Needs pyserial (in the ESP-IDF python env, which tools/esp_flash.sh exports).
Raw bytes go to stdout.
"""
import fcntl
import sys
import termios
import time

import serial


def open_port(port):
    s = serial.Serial()
    s.port = port
    s.baudrate = 115200
    s.timeout = 0.1
    s.dtr = False
    s.rts = False
    s.exclusive = True
    s.open()
    fcntl.ioctl(s.fd, termios.TIOCEXCL)
    return s


def main():
    port, seconds = sys.argv[1], float(sys.argv[2])
    rest = sys.argv[3:]
    reset = "--no-reset" not in rest
    until = rest[rest.index("--until") + 1].encode() if "--until" in rest else None
    seen = b""
    out = sys.stdout.buffer
    try:
        s = open_port(port)
    except (serial.SerialException, OSError) as e:
        sys.stderr.write("esp_serial_capture: %s is busy or unavailable: %s\n" % (port, e))
        sys.exit(3)
    if reset:
        s.dtr = False
        s.rts = True    # EN low: hold the chip in reset
        time.sleep(0.1)
        s.rts = False   # EN high: run from flash
    end = time.time() + seconds
    while time.time() < end:
        try:
            data = s.read(4096)
        except (serial.SerialException, OSError):
            # the USB-Serial/JTAG port re-enumerating: reopen and carry on
            try:
                s.close()
            except Exception:
                pass
            while time.time() < end:
                time.sleep(0.05)
                try:
                    s = open_port(port)
                    break
                except (serial.SerialException, OSError):
                    continue
            continue
        if data:
            out.write(data)
            out.flush()
            if until is not None:
                seen = (seen + data)[-(len(until) + 256):]
                i = seen.find(until)
                if i >= 0 and b"\n" in seen[i:]:
                    break
    s.close()


if __name__ == "__main__":
    main()
