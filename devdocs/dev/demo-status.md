# Demo status — every `examples/**` program, measured

Goal 3 of `the-goal-cross-cross.md` is *"a nice list of working demos"*. This is
that list as MEASURED, one row per program `make demos` discovers (36; esp32 is
cross-only and not in it). Replace the table when you re-measure; do not append.

**Measured 2026-09-19 by frankH.** Two compilers, identical results on every row
except `mandelzoom`'s frame count:

- **pin v411** (`8d9d69bdc`, binary `bc884808fda5`), which is what `make demos` uses;
- **HEAD** binary `7ca269bd75ad` at tree `cbfc1338d`.

The rows marked *fixed* were re-verified with both after their fix landed.

**How each column was measured** (all runs bounded by `timeout 15`, environment
scrubbed with `env -i`, under `GDK_BACKEND=x11 xvfb-run -a`, so no window can
reach a desktop session):

- **builds**: the `make demos` recipe line, same flags (`--threadsafe` for
  palparallel users).
- **runs**: started with stdin `</dev/null` from the repo root; `--smoke` also
  where the source accepts it. "exit 0" means it finished by itself inside 15s.
  "runs until quit" means it was still running at 15s, which is correct for an
  interactive or animated program and says nothing more than "did not crash".
- **GUI window**: default mode (the real event loop), and the biggest X window
  owned by the pid, read with xdotool after about 1s. This is the same check as
  `tools/gui_suite.sh`'s `gui_realwindow`. `--gui-smoke` too where it exists.

**Evidence: what a row's "runs" actually rests on.** A self-quit proves only
that nothing crashed before the timer fired, so it is never counted as a check.

- **asserts**: the demo checks its own result and exits 1 on failure (source read).
- **verdict**: the demo prints its own verdict line and I read that line. That
  `ALL OK` is printed only when every check passed was read in the source for
  bigmath, calcdemo and raytracer, not for the other six. **It exits 0 even when it prints a
  failure** (no nonzero exit path in the source), so a harness reading only rc
  would pass a broken run.
- **checked**: I compared the output with a known answer (given in the row).
- **self-quit**: auto-quits on a timer; says nothing about output.
- **start+EOF**: prints its prompt or screen and exits cleanly when input ends; not driven further.
- **none**: nothing about the output was checked.

| demo | kind | builds | runs | evidence | GUI window | notes |
| --- | --- | --- | --- | --- | --- | --- |
| adventure/adventure | text game | yes | exit 0 from `examples/adventure/`; from the repo root `EInOutError` | start+EOF; scripted `look`/`quit` answered | — | loads `world.dat` CWD-relative, so run it from its directory. *fixed*: spun forever at EOF |
| bignum/bigmath | self-check | yes | ALL OK | verdict | — | |
| bignum/factorial | batch | yes | exit 0 | checked: 1000! has 249 trailing zeros | — | |
| calc/calcdemo | self-check | yes | ALL OK | verdict | — | |
| chess/chess | interactive | yes | exit 0 at EOF | start+EOF | — | |
| fm/fm | TUI | yes | exit 0 at EOF | start+EOF | — | not driven with keys |
| g2048/console_2048 | interactive | yes | exit 0 at EOF | start+EOF | — | |
| gl/triangle | GTK + OpenGL 3.3 | yes | runs until quit (spins) | checked: screen readback under Xvfb (Mesa 4.5 core) shows the GL clear colour and about 33k triangle-coloured pixels, no stderr | **780x560** | *fixed*: GL was imported from a library that does not exist, GL_STATIC_DRAW was wrong, the render callback dropped Sender, and the label was not UTF-8 |
| hello/hello | batch | yes | exit 0 | checked: prints its greeting | — | |
| json/jsondemo | self-check | yes | ALL OK | verdict | — | |
| kiosk | interactive | yes | exit 0 at EOF | checked: `sum 10` = 55, `primes 20` = 8 | — | *fixed*: spun forever at EOF |
| life/life | GTK | yes | `--smoke` exit 0 | self-quit | **800x480** | the window size is the real evidence |
| lisp/lispdemo | self-check | yes | ALL OK | verdict | — | |
| mandelbrot/mandelbrot | self-check | yes | ALL OK | verdict | — | |
| mandelbrot/mandelbrot_gui | GTK | yes | `--smoke`: serial == parallel | asserts (checksum); `--gui-smoke` is self-quit | **920x700** | |
| mandelbrot/mandelbrot_parallel | self-check | yes | CHECKSUM MATCH | asserts | — | |
| mandelbrot/mandelzoom | terminal animation | yes | runs until quit | none | — | no self-exit mode |
| mathf/mathdemo | self-check | yes | ALL OK | verdict | — | |
| maze/maze | batch | yes | exit 0 | none | — | `path cells = 49` not verified |
| net/httpdemo | loopback server + client | yes | exit 0 | checked: three GETs return 200 with the expected bodies, the cookie echoed and gzip decoded | — | 127.0.0.1 only |
| parallel/collatz | self-check | yes | ALL AGREE | asserts | — | |
| parallel/membw | self-check | yes | ALL AGREE | asserts | — | |
| parallel/pow | self-check | yes | ALL AGREE | asserts | — | |
| parallel/primecount | self-check | yes | ALL AGREE, pi = 148933 | asserts, against known constants | — | *fixed*: const `N` was shadowed by the loop variable `n` |
| player/player | terminal video player | yes | usage message, exit 1 | none | — | not run on a video: it needs a file argument |
| primes/sieve | batch | yes | exit 0 | checked: largest prime <= 10^6 is 999983 | — | |
| raytracer/raytracer | self-check | yes | ALL OK | verdict (checksum) | — | |
| raytracer/raytracer_gui | GTK | yes | `--smoke` exit 0 | self-quit | **660x560** | the window size is the real evidence |
| sat/satdemo | self-check | yes | ALL OK | verdict | — | |
| solitaire/console_solitaire | interactive | yes | exit 0 at EOF | start+EOF | — | |
| solitaire_gui/solitaire_gui | GTK | yes | `--smoke` SMOKE OK | asserts (a stock press draws, a resize enlarges cards); `--gui-smoke` is self-quit | **820x640** | |
| sudoku/sudoku | batch | yes | exit 0 | checked: all 3 printed grids are valid sudoku solutions | — | |
| sudoku/sudoku_game | interactive | yes | exit 0 at EOF | start+EOF | — | *fixed*: spun forever at EOF |
| tk/uses_tkinter_and_configparser | compile regression | yes | exit 0 | none: prints `both ok` unconditionally | — | a build test that lives in examples/, not a demo |
| tui/menudemo | TUI | yes | exit 0, `selected=Open` | start+EOF (the default item) | — | |
| vm/vmdemo | self-check | yes | ALL OK | verdict | — | |

**Summary: 36 of 36 build; all 36 run as designed; all 5 GTK demos map a
real window.** On evidence:
- 7 rows assert their own result and exit 1 on failure.
- 9 print a verdict that I read, but exit 0 even on failure.
- 7 were checked against known answers (triangle by screen readback).
- The rest show only start-up, a self-quit, or nothing about the output.

## What this table does NOT show

- **Interactive depth.** The TUI and game rows prove start-up, a prompt and a
  clean EOF, not a played game. Nothing was keyed into `fm` or `menudemo`.
- **Real GPU drivers.** The triangle was verified on Mesa's software
  renderer under Xvfb, not on the desk's NVIDIA driver.
- **The other two goal-3 demos.** lekkerzeilen (NilPy) and busybox (C) are not
  `examples/**` Pascal programs and are tracked on their own umbrellas.
- **Cross targets.** Everything above is x86-64 Linux; esp32 examples are
  skipped by `make demos`. The one cross demo measured so far is
  **`examples/esp32/nilpy-c3`: a static Python application on the ESP32-C3**
  (a class, a list, a loop, `print`), compiled by pxx to machine code and linked
  by ESP-IDF. `./build.sh qemu-assert` boots it under Espressif qemu and diffs
  the console against CPython's output: **OK, one boot, no watchdog over 45 s**
  (2026-09-19, frankS, HEAD binary `035bd63724e1`). **Checked** in this table's
  terms. It needs the compiler fixes landed with it, so until the next pin run
  it as `PXX=compiler/pascal26 ./build.sh qemu-assert`. Not measured: silicon.
  **`examples/esp32/nilpy-s3`: the same program on the ESP32-S3** (windowed
  xtensa; build.sh and main.npy are symlinks into nilpy-c3, the script picks the
  chip from its directory): **OK, one boot**, 2026-09-19, frankS, binary
  `8e9015727927` built from the tree this row landed with. Same pin caveat.
  It also passes `--xtensa-long-calls`, which its build.sh sets (`feature-a-xtensa-should-not-need-a-flag-to-build-a-large-image`).
  Not measured: silicon, and the S3 is the owner's own hardware, so that is the
  next thing worth measuring.
  **`examples/esp32/nilpy-hw-c3` and `-hw-s3`: a static Python application that
  TOUCHES THE HARDWARE** — it drives GPIO 8 and is paced by an ESP-IDF timer
  callback, through two pxx Pascal units that carry a Python surface
  (`lib/rtl/platform/esp/esptimer.pas`, `espgpio.pas`). **OK on both chips, one
  boot** (2026-09-19, frankS, binary `38410ffddc4b`), `./build.sh qemu-assert`.
  **Read its pass narrowly, and this row is where the other two differ:** its
  `main.expected` is the program's SPECIFICATION, not CPython's output — CPython
  cannot run it, since the two imports have no CPython equivalent. What it
  witnesses is that the SDK timer callback fired and the Python loop saw it
  (`timer_ticks()` advancing is the callback having run). **The LED is NOT
  witnessed**: Espressif's qemu does not model the GPIO input path and its
  output path is unobservable, so `gpio_write` executes, returns 0, and nothing
  here can say what the pin did. That half needs silicon, which is also why
  this is the demo worth flashing first.

## Reproduce

The sweep is two small scripts, not a Makefile target. Build as the `demos`
recipe does into a directory, then for each program run it bounded under
`env -i PATH=/usr/bin:/bin HOME=$HOME TERM=xterm GDK_BACKEND=x11 xvfb-run -a`
with `</dev/null`, adding `--smoke` when the source contains `'--smoke'`. For a
GUI binary, launch it under xvfb-run, then take the largest
`xdotool getwindowgeometry` over `xdotool search --pid`. **Keep
`GDK_BACKEND=x11`**: without it, a GTK demo started from a Wayland desktop seat
opens on the owner's desktop and the X-side check reads 0x0.
