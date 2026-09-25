---
title: The ESP32 IDE
order: 31
---

# The ESP32 IDE

`apps/ide/esp` is a small window for working on an ESP32 program. It has a
folder tree, an editor, and a chip selector with a **Detect** button. One
**Build+Flash** button builds the project for the chip on the USB port, writes
it to the board, and then shows what the board prints. It is written in Pascal
and built with PXX, like the [Eliah IDE](../examples/index.md#the-eliah-ide),
and shares Eliah's core. The name `esp` is a working name.

Everything on this page was run from a checkout at `9fa9c55901` with pin v426
(compiler sha256 `7b742af6f9df…`) on 2026-09-25. The board steps were run on
an ESP32-S3 devkit (`/dev/ttyACM0`). No ESP32-C3 board has been tried; see
[What is and is not proven](./esp32.md#what-is-and-is-not-proven).

## What you need

- A PXX checkout, and the GTK 3 development files that the
  [Eliah IDE](../examples/index.md#the-eliah-ide) also needs.
- ESP-IDF v6.0.1 in `~/esp/esp-idf`, or wherever `ESP_IDF_DIR` points. Step 1
  of [Getting started on the ESP32](./esp32.md) installs it.
  The IDE loads ESP-IDF's environment itself, so you do not need to source
  `export.sh` first.
- **Permission to open the serial port.** On most Linux systems the board's
  port belongs to the `dialout` group. To check whether you are in it:

  ```sh
  id -nG | tr ' ' '\n' | grep -x dialout
  ```

  If that prints nothing, add yourself with `sudo usermod -aG dialout $USER`,
  then **log out and back in**. The new group only reaches programs started
  after you log in again.

## Build and start it

From the root of the checkout:

```sh
apps/ide/esp/build.sh                    # built: apps/ide/esp/espide
apps/ide/esp/espide                      # opens examples/esp32
apps/ide/esp/espide examples/esp32/hello-s3
```

The build uses the pinned compiler and takes about ten seconds.

## Using it

1. **Open a folder.** Type a path in the box at the top left and press
   **Open**, or pass the path on the command line. The tree lists its files and
   subfolders, but not `build/` or hidden entries. Click a file to open it in
   the editor. **Save** writes it back.
2. **Pick the project.** A project is a folder with a `CMakeLists.txt` and a
   `build.sh`, like every `examples/esp32/<name>-<chip>` folder. The IDE uses
   the project that holds the file or folder you clicked. So you can open all
   of `examples/esp32` and click into the project you want. The status line
   names the project and the chip it builds for: the folder's `-s3`, `-c3` or
   `-s2` suffix, or else the chip named in its `build.sh` or `sdkconfig`.
3. **Detect.** The IDE asks every `/dev/ttyACM*` and `/dev/ttyUSB*` port which
   chip is behind it, using `esptool chip-id`. **This resets the board.** The
   status line then names each board found and its port.
4. **Chip.** Leave the selector on `auto` to follow the board you detected, or
   pick `ESP32-S3`, `ESP32-C3` or `ESP32-S2` by hand.
5. **Build+Flash.** This first saves the open file. Then it runs
   `tools/esp_flash.sh --project <project> --chip <chip> --port <port>`, which
   builds with the project's own `build.sh`. The log appears in the lower pane
   as the build runs. A build can take several minutes: ESP-IDF configures
   a project from scratch the first time, and some examples, `hello-s3` among
   them, run `idf.py set-target` in their `build.sh`, which does that on every
   build. After the image is written, the pane
   shows the board's first few seconds of output. Then it switches to the
   **serial monitor**.
6. **Monitor.** The monitor reads the port at 115200 baud and shows
   everything the board prints, until you press **Stop**. **Monitor** reopens
   it on the last board. Detect and Build+Flash close the monitor first,
   because they need the port themselves. The pane keeps the most recent
   32 KB of output.

On the S3 devkit, `hello-s3` built, flashed and printed
`PXX hello from Pascal S3: i=1` to `i=5`. `monitor-s3` flashed, and its
once-a-second reports kept arriving in the monitor pane after the flash:

```text
#  7 mean 3858 range 3839..3876 trend flat    frames 110 free 262068
#  8 mean 3859 range 3799..3879 trend flat    frames 126 free 262072
#  9 mean 3859 range 3838..3879 trend flat    frames 142 free 262068
```

## When it refuses

The IDE does not guess a chip or a board. In these cases it stops and says
why, word for word as below.

**Chip on `auto` and no board found.** It will not build for a default chip:

```text
No board detected: connect an ESP32 board and press Detect, or pick the chip by hand.
```

**A folder that is not an ESP-IDF project**, such as a bare `main.pas` with no
`CMakeLists.txt`. Here the folder was called `fixtures`:

```text
fixtures is not an ESP-IDF project (it has no CMakeLists.txt and build.sh): copy a project from examples/esp32 and put your main.pas or main.npy in its main/ folder.
```

**The project and the board are different chips.** Here a `-c3` project met
an S3 board:

```text
This project builds for the ESP32-C3, not the ESP32-S3: open a project for the ESP32-S3 or connect an ESP32-C3.
```

**The selector and the board disagree.** Here the selector said C3 and an S3
was plugged in:

```text
The chip selector says ESP32-C3 but the connected board is an ESP32-S3.
```

**No permission to open the port.** Detect reports it for each port:

```text
Detect: /dev/ttyACM0: permission denied: your user needs the dialout group (add it, then log in again)
```

## Without clicking

Two options run the IDE unattended. The window still opens, so under a
headless session run it with `xvfb-run -a`.

```sh
apps/ide/esp/espide --gui-smoke                           # opens, paints, prints GUI SMOKE OK
apps/ide/esp/espide --auto examples/esp32/hello-s3 10     # detect, build+flash, monitor 10 s
```

`--auto` prints the log to standard output and ends with
`ESPIDE-AUTO-COMPLETE rc=<n>`. `rc` is 0 when the board was flashed, 1 when
the build or the flash failed, and 2 when the IDE refused, for any of the
reasons above.

The decisions behind the refusals live in `apps/ide/garin/espproj.pas`, and
`apps/ide/test.sh` tests them without opening a window. With pin v426 it
reports `202 passed, 0 failed`.

## Next

- [Getting started on the ESP32](./esp32.md)
- [ESP32 / Microcontrollers](../targets/esp32.md)
- [ESP32 peripherals](../library/esp.md)
