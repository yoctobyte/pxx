---
title: The ESP32 IDE
order: 31
---

# The ESP32 IDE

`apps/ide/esp` is a small window for working on an ESP32 program. It has a
menu bar, a folder tree, an editor, a chip selector, a port selector and a
**Detect** button. One **Build+Flash** button builds the project for the chip
on the USB port, writes it to the board, and then shows what the board prints. It is written in Pascal
and built with PXX, like the [Eliah IDE](../examples/index.md#the-eliah-ide),
and shares Eliah's core. The name `esp` is a working name.

The window, menus and messages on this page were re-checked on 2026-09-27
against the source at `e4cbac2491` with pin v445 (compiler sha256
`caf21ac399f1`): `./espide.sh --gui-smoke` printed `GUI SMOKE OK`, and
`apps/ide/test.sh` reported `304 passed, 0 failed`. Detect and Build+Flash
were not pressed for that check. The board steps below were run earlier, from
a checkout at `9fa9c55901` with pin v426 (compiler sha256 `7b742af6f9df…`) on
2026-09-25, on an ESP32-S3 devkit (`/dev/ttyACM0`). These steps have not been repeated on
an ESP32-C3 board, although the C3 examples have run on one; see
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

`espide.sh` at the root of the checkout does both:

```sh
./espide.sh                              # opens examples/esp32
./espide.sh examples/esp32/hello-s3      # opens that folder
```

It builds the IDE first when the binary is missing or older than its sources
(`apps/ide/esp`, `apps/ide/garin`, `lib/pcl`, `lib/rtl`) or the pinned
compiler, which takes about ten seconds. Then it starts the IDE with your
arguments. It works from any directory. A relative folder is looked up in your
current directory first, then in the checkout, so
`examples/esp32/hello-s3` works from anywhere. If you are not in the
`dialout` group, it prints one line saying how to fix that, and starts the
IDE anyway:

```text
espide.sh: to use the board's serial port, run: sudo usermod -aG dialout <you>  -- then log out and back in.
espide.sh: you are in the dialout group, but this login predates it: log out and back in to use the board's serial port.
```

The first line is for a user who is not in the group. The second is for a
user who was added but has not logged in again since.

To build and run it by hand instead:

```sh
apps/ide/esp/build.sh                    # built: apps/ide/esp/espide
apps/ide/esp/espide examples/esp32/hello-s3
```

## Using it

1. **Open a folder.** Use **File › Open Folder or Project…** to pick one in a
   folder chooser, type a path in the box at the top left and press **Open**,
   or pass the path on the command line. **File › Open File…** opens a single
   file. The tree lists folders first, collapsed except the top one, and leaves
   out `build/` and hidden entries. Click a file to open it in the editor.
   **Save** (or **File › Save**) writes it back.
2. **Pick the project.** A project is a folder with a `CMakeLists.txt` and a
   `build.sh`, like every `examples/esp32/<name>-<chip>` folder. The IDE uses
   the project that holds the file or folder you clicked. So you can open all
   of `examples/esp32` and click into the project you want. The status line
   names the project and the chip it builds for: the folder's `-s3`, `-c3` or
   `-s2` suffix, or else the chip named in its `build.sh` or `sdkconfig`.
3. **The boards line.** Below the toolbar, the IDE lists the boards attached
   right now, by their `/dev/serial/by-id` names and USB bridge, **without
   opening any port** (opening one resets the board). A board shows its chip,
   MAC and revision only after Detect has asked it. The **Port** selector holds
   `auto` and each attached board.
4. **Detect.** The IDE asks **one** port which chip is behind it, using
   `esptool chip-id`. **This resets that board, and no other.** Which port:
   the one picked in **Port**; otherwise, with the chip selector set, the one
   board whose USB descriptor can be that chip; otherwise, when only one board
   is attached, that one. When several boards could be meant, it refuses and
   lists them instead of resetting them all (see below).
5. **Chip.** Leave the selector on `auto` to follow the board you detected, or
   pick `ESP32`, `ESP32-S3`, `ESP32-C3` or `ESP32-S2` by hand.
6. **Build+Flash.** This first saves the open file. Then it runs
   `tools/esp_flash.sh --project <project> --chip <chip> --port <port>`, which
   builds with the project's own `build.sh`. The log appears in the lower pane
   as the build runs. A build can take several minutes: ESP-IDF configures
   a project from scratch the first time, and some examples, `hello-s3` among
   them, run `idf.py set-target` in their `build.sh`, which does that on every
   build. After the image is written, the pane
   shows the board's first few seconds of output. Then it switches to the
   **serial monitor**.
7. **Monitor.** The monitor reads the port at 115200 baud and shows
   everything the board prints, until you press **Stop**. **Monitor** reopens
   it on the last board. Detect and Build+Flash close the monitor first,
   because they need the port themselves. The pane keeps the most recent
   32 KB of output.

**Settings.** **Settings › ESP-IDF** shows the ESP-IDF the IDE found, with
its version and path, or `ESP-IDF: not found` and where to get it; the status
line shows the same. It is read from files, so nothing runs to find it.
**Settings › Libraries…** sets, per project, extra unit search folders (each
becomes a `-Fu`), extra ESP-IDF component folders and extra components the
project `REQUIRE`s. They are saved in `espide.cfg` in the project folder, so
they travel with the project.

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

**Several boards attached, and nothing says which one to ask.** Detect will
not reset boards to find out; pick one in **Port**:

```text
Detect: several boards are attached and nothing says which one to ask (Detect resets the board it asks). Pick a port: ...
```

With the chip selector set and more than one board that could be that chip,
it says `several attached boards could be an ESP32-C3, and finding out which
would reset them. Pick a port:` and lists them.

**No permission to open the port.** Detect reports it for the port it asked:

```text
Detect: /dev/ttyACM0: permission denied: your user needs the dialout group (add it, then log in again)
```

## Without clicking

Two options run the IDE unattended. The window still opens, so under a
headless session run it with `xvfb-run -a`.

```sh
./espide.sh --gui-smoke                                     # opens, paints, prints GUI SMOKE OK
./espide.sh --auto --port <port> examples/esp32/hello-s3 10 # detect, build+flash, monitor 10 s
```

`--port` names the board, so an unattended run touches no other. `--auto`
prints the log to standard output and is meant to end with
`ESPIDE-AUTO-COMPLETE rc=<n>`: `rc` is 0 when the board was flashed, 1 when
the build or the flash failed, and 2 when the IDE refused, for any of the
reasons above.

**Currently, after a successful flash `--auto` does not end.** It opens the
monitor, prints `--- serial <port> (115200) ---`, and then waits forever: the
monitor time is ignored and `ESPIDE-AUTO-COMPLETE` is never printed. A refusal
(`rc=2`) and a failed build (`rc=1`) do end. Until this is fixed, run `--auto`
under `timeout` and judge the flash by the `Build+Flash: done` line in its
output. The fix is in progress.

The decisions behind the refusals live in `apps/ide/garin/espproj.pas`, and
`apps/ide/test.sh` tests them without opening a window, including which port
Detect may ask. With pin v445 it reports `304 passed, 0 failed`.

## Next

- [Getting started on the ESP32](./esp32.md)
- [ESP32 / Microcontrollers](../targets/esp32.md)
- [ESP32 peripherals](../library/esp.md)
