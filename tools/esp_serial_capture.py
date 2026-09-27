#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Reset an ESP32 through its serial port's RTS/DTR lines and capture what it
prints, from the boot ROM on, for N seconds.

    esp_serial_capture.py <port> <seconds> [--no-reset]

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

Needs pyserial (in the ESP-IDF python env, which tools/esp_flash.sh exports).
Raw bytes go to stdout.
"""
import sys
import time

import serial


def open_port(port):
    s = serial.Serial()
    s.port = port
    s.baudrate = 115200
    s.timeout = 0.1
    s.dtr = False
    s.rts = False
    s.open()
    return s


def main():
    port, seconds = sys.argv[1], float(sys.argv[2])
    reset = "--no-reset" not in sys.argv[3:]
    out = sys.stdout.buffer
    s = open_port(port)
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
    s.close()


if __name__ == "__main__":
    main()
