# apps/ide — the Eliah / Ilja IDE

A single-window IDE, Lazarus/Delphi-inspired but deliberately stripped: one
sizable window, **no multi-window, no modal forms, no scattered subwindows**.
Everything lives tiled in one window.

## Naming (Hebrew)

- **garin** (גרעין) = *kernel / core*. The render-agnostic engine: editor buffer,
  project model, the designed-form document, the builder. Both faces grow from
  this seed.
- **eliah** = *Elijah* (GTK face — posix + GTK).
- **ilja** = *Elijah* again, a second transliteration (ANSI/TUI face — posix +
  terminal). Same prophet, two faces; same product, two renderers.

```
apps/ide/
  garin/   # core — shared, render-agnostic
  eliah/   # GTK face   (build first)
  ilja/    # ANSI face  (later)
  esp/     # GTK face for ESP32 boards (working name; awaiting its Hebrew one)
```

## Hard rules

- **Pure box emulation** for form preview: the designer paints plain boxes with
  content and an estimated size. It does **not** instantiate live widgets, and we
  do **not** compile design-mode components into the IDE. No design-time/runtime
  `TComponent` split, no `TComponent` linked.
- GUI and TUI have different requirements: only the **data models** (garin) are
  shared. Rendering, input, and layout are reimplemented per face.

## Build (Eliah, M0)

```sh
apps/ide/build.sh        # uses the pinned stable compiler
apps/ide/eliah/eliah     # run
```

## The ESP32 face (`apps/ide/esp`, working name)

A folder tree, an editor, and one button that builds an ESP-IDF project for
the chip on the USB port, flashes it, and follows its serial output.

```sh
./espide.sh [folder]                         # from the repo root: builds if stale, then starts
apps/ide/esp/build.sh                        # or by hand: pinned stable compiler
apps/ide/esp/espide [folder]                 # default: examples/esp32
apps/ide/esp/espide --auto <project> [secs]  # detect, build+flash, monitor secs, exit
```

`espide.sh` rebuilds when the binary is missing or older than anything in
`apps/ide/esp`, `apps/ide/garin`, `lib/pcl` or `lib/rtl`, or than the pinned
compiler. It works from any directory, and it prints a one-line fix, then
starts anyway, when the user is not in the `dialout` group.

- **A project** is what `tools/esp_flash.sh --project` builds: a folder with
  `CMakeLists.txt` and `build.sh`, like every `examples/esp32/<name>-<chip>`.
  The face walks up from the selected file to find one; any other folder is
  refused in one sentence that points at `examples/esp32`.
- **The chip.** `Detect` asks every `/dev/ttyACM*` and `/dev/ttyUSB*` with
  `esptool chip-id` (which resets the board). The chip selector's `auto`
  follows the detected board, and **with no board it refuses and says so. It
  never builds for a default chip.** A project whose folder suffix, or
  `set-target`, names another chip than the board is refused too.
- **Build+Flash** runs `tools/esp_flash.sh --project` (the project's own
  `build.sh` holds the flags), then opens the port as a serial monitor
  (115200). `Stop` ends a running child; Detect and Build+Flash close the
  monitor first, because esptool needs the port.
- Serial ports need the `dialout` group. A relative folder argument is looked
  up in the current directory first, then in the checkout.
- The decisions live in `garin/espproj.pas` and are tested headlessly by
  `apps/ide/test.sh` (bochan); the face only renders them.
