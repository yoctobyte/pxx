---
title: Examples
order: 55
---

# Examples

A showcase of programs PXX compiles today: small Pascal demos, terminal and GUI
applications, Python (NilPy) programs, ESP32 firmware, and real third-party C
code such as BusyBox, SQLite, zlib and Lua. The sources for the demos live
under `examples/` in the checkout.

**Every entry on this page was compiled and run.** Nothing is listed on the
strength of a test that once passed or a claim in another document.

> **Verified 2026-09-24** on an x86-64 Linux host, with the pinned compiler
> **v423** (`stable_linux_amd64/default/pinned`, sha256 `113a515bbdc9…`), at
> checkout `02bd18fa0`. Where a row was measured differently, it says so. A
> later pin may behave differently in either direction; re-run a command to
> check.
>
> **Re-checked 2026-09-25 with pin v424** (commit `0a3a7b5b4`, sha256
> `93a336a7ba85…`). All 36 example programs built. The batch and parallel
> programs printed output byte-identical to v423's, apart from timing figures,
> and every binary is the same size as under v423. The screenshots, the ESP
> runs and the C-library rows were not redone for v424.

## Quick start

```sh
./install.sh --yes      # checks the pinned compiler, writes the ./pxx wrapper
./demos.sh list         # the launcher's menu
./demos.sh all          # build every demo, run the batch ones
```

On the verification host `./demos.sh all` reported
`27 built, 0 failed (12 batch ran; tty/gui built-only)`. `make demos` builds
the complete set of 36 programs under `examples/` (esp32 excluded), and all 36
built.

To build one program yourself:

```sh
./pxx examples/json/jsondemo.pas /tmp/jsondemo
/tmp/jsondemo
```

Programs that use `parallel for` need `--threadsafe`, and the compiler refuses
them without it:

```sh
./pxx --threadsafe examples/parallel/primecount.pas /tmp/primecount
```

PXX writes its own ELF executables and needs no external linker. Programs that
don't use a system GUI library come out as a single static file with no
dynamic loader, and the hello-world is **4,544 bytes**. The GTK, OpenGL and
SDL2 programs below link those system libraries dynamically.

## Pascal: batch programs

Each of these runs to completion and checks its own result. The ones marked
**ALL OK** compare against built-in expected values and print a verdict.

| Program | Source | What it shows | Result on the verification run | Binary |
| --- | --- | --- | --- | --- |
| hello | `examples/hello/hello.pas` | The smallest program | `Greetings from PXX` | 4.4 KB |
| primes | `examples/primes/sieve.pas` | Bit-packed sieve of Eratosthenes | 78,498 primes ≤ 1,000,000 | 103 KB |
| sudoku | `examples/sudoku/sudoku.pas` | Backtracking solver | three puzzles solved | 29 KB |
| factorial | `examples/bignum/factorial.pas` | Big-integer factorial | 1000! has 2,568 digits | 107 KB |
| bigmath | `examples/bignum/bigmath.pas` | Arbitrary-precision arithmetic, modular power | ALL OK | 136 KB |
| json | `examples/json/jsondemo.pas` | JSON parse and emit, escapes, Unicode | ALL OK | 502 KB |
| sat | `examples/sat/satdemo.pas` | DPLL SAT solver, including pigeonhole UNSAT | ALL OK | 117 KB |
| mathf | `examples/mathf/mathdemo.pas` | Floating-point math library | every check `ok` | 187 KB |
| maze | `examples/maze/maze.pas` | Maze generation and solving | seeded maze with solved path | 106 KB |
| mandelbrot | `examples/mandelbrot/mandelbrot.pas` | ASCII Mandelbrot set | ALL OK (checksum) | 136 KB |
| raytracer | `examples/raytracer/raytracer.pas` | Ray tracer, headless | ALL OK (checksum) | 545 KB |
| vm | `examples/vm/vmdemo.pas` | Tiny bytecode VM and assembler | ALL OK | 123 KB |
| calc | `examples/calc/calcdemo.pas` | Expression evaluator, including rejects | ALL OK | 109 KB |
| lisp | `examples/lisp/lispdemo.pas` | Lisp with closures and a cell arena | ALL OK | 122 KB |
| httpdemo | `examples/net/httpdemo.pas` | HTTP server and client on one coroutine reactor (loopback, no network needed) | three requests, cookie and gzip | 593 KB |

The maze demo draws its own solution:

```text
#########################
#*#   #                 #
#*# ### ######### ##### #
#*#   # #*******#     # #
#*# # # #*#####*### # # #
#*# #   #*#***#***# # # #
#*##### #*#*#*###*### # #
#*****# #***#*# #***# # #
#####*# #####*# ###*# ###
#   #*#     #*#*****#   #
# ###*##### #*#*####### #
#*****#     #*#*#  ***# #
#*####### ###*#*###*#*# #
#*#*****# #***#*****#*# #
#*#*###*###*#########*# #
#***#  *****#        ***#
#########################
seed 12345  size 12x8  path cells = 49
```

The HTTP demo runs a server and a client in one process:

```text
GET /        -> 200 OK
  body:   Welcome to frank2 net
  cookie: sid=demo123
GET /me      -> 200 OK  (cookie sent back)
  body:   hello sid=demo123
GET /data.gz -> 200 OK  (gzip, decoded transparently)
  body:   hello world
done
```

## Pascal: parallel programs

`uses palparallel` gives `parallel for` loops with reductions and a choice of
work distribution. Build these with `--threadsafe`.

| Program | Source | What it shows |
| --- | --- | --- |
| primecount | `examples/parallel/primecount.pas` | Even load: prime count over 2..2,000,000 |
| collatz | `examples/parallel/collatz.pas` | Very uneven load, where on-demand distribution pays off |
| pow | `examples/parallel/pow.pas` | Compute-bound hashing, near-linear scaling |
| membw | `examples/parallel/membw.pas` | Memory-bound against compute-bound reduction |

Each program checks that every distribution produces the same answer as the
serial loop:

```text
Prime count over 2..2000000   workers=12
primes     = 148933   max gap = 132
serial     : 2951987 us
pdChunked  : 653334 us   speedup 451 /100x
pdOnDemand : 592328 us   speedup 498 /100x
(even load: pdChunked ~= pdOnDemand here, unlike collatz)
ALL AGREE — count matches pi(LIMIT), reductions identical across distributions
```

The timings come from a shared 12-core machine that was busy with other work,
so read the speedups as indicative only. The correctness line is the claim.

## Pascal: terminal applications

Full-screen terminal programs using PXX's own terminal units: no curses and no
C library. The screenshots were captured from each program running in an
`xterm`, driven by scripted keystrokes.

| Program | Source | |
| --- | --- | --- |
| 2048 | `examples/g2048/console_2048.pas` | ![2048 in a terminal](../assets/showcase/g2048.png) |
| Klondike solitaire | `examples/solitaire/console_solitaire.pas` | ![Klondike solitaire in a terminal](../assets/showcase/solitaire.png) |
| Sudoku game | `examples/sudoku/sudoku_game.pas` | ![Interactive Sudoku](../assets/showcase/sudoku_game.png) |
| Text adventure | `examples/adventure/adventure.pas` (run from `examples/adventure/`, it reads `world.dat`) | ![Text adventure with pixel-art scene](../assets/showcase/adventure.png) |
| Menu widgets | `examples/tui/menudemo.pas` | ![TUI menu](../assets/showcase/menudemo.png) |
| File browser | `examples/fm/fm.pas` (`fm --interactive [path]`; with no flag it renders once and exits) | ![Terminal file browser](../assets/showcase/fm.png) |
| Mandelbrot zoom | `examples/mandelbrot/mandelzoom.pas`: animated truecolor zoom using integer asm kernels on all cores | ![Mandelbrot zoom in a terminal](../assets/showcase/mandelzoom.png) |
| Video player | `examples/player/player.pas`: `player <video>`, decodes through an `ffmpeg` child process and draws in truecolor blocks | ![Terminal video player](../assets/showcase/player.png) |

The chess engine (`examples/chess/chess.pas`) and the kiosk are
line-oriented, so they are shown as text. At start-up the engine prints the
board, its move-generation counts (perft), which match the published values
for the start position, and its opening choice. It then takes commands
(`print`, `fen`, `perft <n>`, `go <depth>`, `quit`):

```text
   a b c d e f g h
White to move

perft(1) = 20
perft(2) = 400
perft(3) = 8902
perft(4) = 197281

bestmove e2e4  score 10  nodes 40793
chess>
```

`examples/kiosk.pas` is the small program that runs inside the
[minimal Linux system](./minimal-linux-system.md):

```text
kiosk> about
pxx self-hosting Pascal compiler, static, no libc.
kiosk> sum 100
sum 1..100 = 5050
kiosk> primes 50
primes below 50 = 15
```

## Pascal: GUI applications

GTK 3 applications, two of them drawing with OpenGL. These need the GTK 3
development headers and libraries on the build host. The screenshots were
taken on a virtual X display with software OpenGL, so the render times and
frame rates shown inside them are not representative of a real GPU.

| Program | Source | |
| --- | --- | --- |
| OpenGL triangle | `examples/gl/triangle.pas` | ![Rotating OpenGL triangle](../assets/showcase/triangle.png) |
| Game of Life | `examples/life/life.pas` | ![Conway's Game of Life with controls](../assets/showcase/life.png) |
| Mandelbrot explorer | `examples/mandelbrot/mandelbrot_gui.pas`: drag to pan, click to zoom, rendered on every core | ![Mandelbrot explorer](../assets/showcase/mandelbrot_gui.png) |
| Ray tracer | `examples/raytracer/raytracer_gui.pas`: reflective spheres, interactive camera | ![Ray-traced spheres](../assets/showcase/raytracer_gui.png) |
| Solitaire | `examples/solitaire_gui/solitaire_gui.pas` | ![Klondike solitaire, GUI](../assets/showcase/solitaire_gui.png) |

### The Eliah IDE

`apps/ide/` is a larger application built with PXX: a single-window IDE,
Lazarus- and Delphi-inspired but deliberately stripped down, with everything
tiled into one window. It is early work and the layout still shows it. It also
doubles as a real-world stress test for the compiler. It builds in about nine
seconds, and its headless core test reported `168 passed, 0 failed`.

```sh
apps/ide/build.sh       # builds apps/ide/eliah/eliah with the pinned compiler
apps/ide/test.sh        # the render-agnostic core, tested without any GUI
```

![The Eliah IDE window](../assets/showcase/eliah.png)

The components use a Hebrew naming scheme. Every name transliterates a word
tied to the prophet Elijah and the theme of testimony:

| Name | Hebrew | Meaning | Role |
| --- | --- | --- | --- |
| `garin` | גרעין | kernel / core | The render-agnostic engine: editor buffer, project model, the designed-form document and the builder. Both faces grow from this seed. |
| `eliah` | אליה | Elijah | The GTK face: the graphical IDE window. |
| `ilja` | איליה | Elijah | The ANSI/TUI face: the same prophet, a second face. |
| `bochan` | בוחן | examiner | The headless test driver for `garin`. It links no GUI or TUI face, which proves the core is render-agnostic. |
| `eduth` | עדות | testimony | The validator `bochan` reports to. It witnesses results, tallies pass and fail, and gives a verdict. |

## Python (NilPy)

NilPy is PXX's Python-shaped frontend. It compiles a static subset of Python
straight to machine code, with no interpreter at run time. Compatibility runs
one way: a program in the supported subset should give CPython's answers, and
NilPy also accepts some things CPython rejects. It is younger than the Pascal
frontend and has known gaps.

### nilsh: a BusyBox-style shell

`examples/shell/nilsh.npy` is a single binary whose commands are built-in
applet functions, with no fork and no exec. The same source is meant to run as
a Linux process or as an ESP32 task set. It plays a scripted session:

```sh
./pxx examples/shell/nilsh.npy /tmp/nilsh && /tmp/nilsh
```

```text
$ help
applets: echo cat ls wc head tail grep upper rev help
$ echo one two three | wc
1 3 13
$ echo nilsh | upper
NILSH
$ echo nilsh | rev
hslin
$ echo alpha beta | cat | upper
ALPHA BETA
```

### lekkerzeilen: a 3D sailing simulator

lekkerzeilen is a separate project: a boat simulator on the real Dutch rivers,
built from open elevation, building and waterway data and rendered with SDL2
and OpenGL. It is written in ordinary Python and runs under CPython through
`ctypes`. The **same source** compiles with PXX to a native binary that talks
to SDL2 and OpenGL directly. It compiles to about 11.6 MB of machine code with
one command, run from the PXX checkout with the lekkerzeilen checkout beside
it (lekkerzeilen's own `runbin.sh` does the same):

```sh
stable_linux_amd64/default/pinned --threadsafe \
    -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES \
    ../lekkerzeilen/lekkerzeilen/__main__.py ../lekkerzeilen/bin/lekkerzeilen
```

The binary looks for its `world/` data relative to its own location, so keep
it in the project's `bin/` directory.

![lekkerzeilen on the same river under CPython and under PXX](../assets/showcase/lekkerzeilen-side-by-side.png)

Both screenshots show the same built scene, the same launch and the same
1280×720 window. They were taken on 2026-09-24, from lekkerzeilen commit
`9db2e38` without changes, on the PXX side built with pin v423. Each is a
single frame captured shortly after start-up, which is why the camera views
differ.

**It compiles and runs. It is not yet as fast as CPython.** The project's own
frame-rate measurement of this scene is **PXX 1.89 fps against CPython 37.1 fps**:
the median over 20-frame windows of 150-second runs, with audio and vsync on,
on one machine, one program at a time. That measurement was taken by the
lekkerzeilen project on **pin v416**, not re-run for this page. That
measurement's own notes list compiler fixes that landed after v416, so a v423
figure may differ. The gap is the work in progress; the result that stands is
that a large 3D Python application with sound builds into one native binary
and runs.

## ESP32

PXX cross-compiles to the ESP32-S3 (Xtensa) and the ESP32-C3 (RISC-V). A
program becomes a relocatable object that the normal ESP-IDF build links as
`app_main`. That includes a Python program, which becomes machine code on the
chip with no interpreter. The examples live in `examples/esp32/`, one ESP-IDF
project per program and chip. The units they use are documented in
[ESP32 peripherals](../library/esp.md).

For this page, each one below was **built with pin v423 and booted under
Espressif's QEMU**. Its console output was checked against the program's
`main.expected` file or its own verdict line. They were not run on a physical
board for this page. The prerequisite is the ESP-IDF toolchain
(`. ~/esp/esp-idf/export.sh`).

| Example | Chip | Language | Command | Result |
| --- | --- | --- | --- | --- |
| hello | S3, C3 | Pascal | `tools/esp_run.sh --chip esp32s3 examples/esp32/hello-s3/main/main.pas` | prints its five lines and `sum 1..5 = 15` |
| nilpy-s3, nilpy-c3 | S3, C3 | Python | `cd examples/esp32/nilpy-s3 && ./build.sh qemu-assert` | output identical to CPython's |
| nilpy-hw-s3, nilpy-hw-c3 | S3, C3 | Python | `./build.sh qemu-assert` | GPIO and timer calls from Python match `main.expected` |
| isrctx-c3 | C3 | Pascal | `./build.sh qemu-assert` | task context and interrupt context both witnessed |
| timer-s3, timer-c3 | S3, C3 | Pascal | `./build.sh qemu` | five ticks, `status=0` |
| fs-c3 | C3 | Pascal | `./build.sh qemu` | FAT mount, write, seek and read back: `esp-pal-file-io-WORKS` |
| dns-c3 | C3 | Pascal | `./build.sh qemu` | lwIP resolver smoke test, `status=0` |
| net-c3 | C3 | Pascal | `./build.sh qemu` | network smoke test, `status=0` |
| gpio-c3 | C3 | Pascal | `./build.sh qemu` | GPIO configuration runs. QEMU delivers no input edges, and the program reports exactly that |

`tools/esp_run.sh` compiles with the in-tree compiler unless
`ESP_RUN_PXX="$PWD/stable_linux_amd64/default/pinned"` is set; the path must be
absolute, because the script compiles from inside the ESP-IDF project. The `build.sh`
scripts default to the pinned compiler.

The Python program from `nilpy-s3` is ordinary Python:

```python
class Boat:
    def __init__(self, name, speed):
        self.name = name
        self.speed = speed

    def eta(self, dist):
        return dist // self.speed

def main():
    fleet = [Boat("Aurora", 6), Boat("Wind", 8), Boat("Kees", 5)]
    total = 0
    for b in fleet:
        t = b.eta(120)
        total += t
        print(b.name, t)
    print("total", total, len(fleet))

main()
```

On the emulated ESP32-S3 it prints the same bytes CPython prints on a desktop:

```text
Aurora 20
Wind 15
Kees 24
total 59 3
```

### On a real ESP32-S3

Separately from the QEMU runs above, the ESP lane flashed eight examples to an
ESP32-S3 board. That run used a development compiler (binary sha256
`bb17d23beea5`, tree `54a8835dd`), not pin v423.

| Example | Language | Result on the board |
| --- | --- | --- |
| nilpy-s3, nilpy-hw-s3 | Python | output matches `main.expected` |
| gpio-edge-s3 | Pascal | output matches `main.expected`: real input edges, which QEMU cannot deliver |
| adc-s3 | Pascal | output matches `main.expected`: real ADC readings |
| hello-s3, timer-s3, rgb-s3 | Pascal | run as intended, checked by eye (no `main.expected`) |
| wifi-ap-s3 | Pascal | starts the access point and reaches `HTTP server listening on port 80`; no client connected during the test |

**These are single runs, not long ones.** The same examples looped for minutes
showed the Python programs leaking memory on every run (`adc-s3` ran out of
memory after about twelve runs). The causes are known and a fix is being
landed. Until then, do not treat the Python examples as safe for long-running
use. The Pascal `rgb-s3` stayed flat over the same test.

Still unverified: `adc-c3` and `gpio-edge-c3`, because there was no C3 board
and QEMU delivers no ADC readings or GPIO edges; and `hello-s2`, which builds
but has not been run. `tools/esp_flash.sh --project examples/esp32/<name>`
builds, flashes and checks an example on a board.

## Real C programs

PXX's C frontend compiles third-party C as released, together with PXX's own
C runtime (`lib/crtl`) in place of glibc. There is one exception. zlib is
built as a single translation unit, where one anonymous `typedef struct` would
be repeated, and that is invalid C, which GCC rejects too. So the recipe gives
that struct a tag in a copy of `gzguts.h`. The results below are static
executables with no dynamic loader and no external C library. The sources are
fetched on demand, not stored in the repository:

```sh
tools/install_lib_candidates.sh busybox sqlite zlib lua cjson quickjs
```

| Program | Version | How it was checked | Binary |
| --- | --- | --- | --- |
| **BusyBox**, unity build | 1.36.1 | `tools/busybox_diff.sh --pinned --targets x86_64`: applets `cat` and `echo` as one translation unit; output byte-identical to a GCC build over 29 cases | 171 KB |
| **BusyBox**, linked by PXX itself | same | `tools/busybox_diff.sh --pinned --pxx-link --targets x86_64 --applets "cat echo ls wc sort ash"`: 55 objects linked by `pascal26 --link` with no external linker; no `PT_INTERP`; byte-identical to GCC over 82 cases | 20 MB |
| **SQLite** | 3.46.0 | amalgamation plus a ten-line `sqlite3_exec` driver; the SQL session below | 3.3 MB |
| **zlib** | 1.3.1 | zlib's own `test/example.c`: output byte-identical to the same program built by GCC | 1.4 MB |
| **Lua** | 5.4.7 | `test/lua/*.lua` against expected output; the stock `lua.c` interpreter also builds and runs | 1.0 MB |
| **cJSON** | 1.7.18 | `test/cjson/*.json` round-trip, all five match | 137 KB |
| **QuickJS** (quickjs-ng) | 0.9.0 | `./pxx -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/quickjs test/quickjs/runner.c qjs` (about 11 s), then `./qjs "$(cat test/quickjs/smoke.js)"`: output byte-identical to `test/quickjs/smoke.expected`. Checked 2026-09-25 with pin v424 at checkout `a515adf81`; it needs the C runtime from that checkout or later | 4.9 MB |

SQLite, compiled by PXX from the single-file amalgamation:

```sh
./pxx -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/sqlite driver.c /tmp/sqlmini
/tmp/sqlmini "create table boats(id integer primary key, name text, knots real);
  insert into boats(name, knots) values ('Aurora', 6.5), ('Wind', 8.0), ('Kees', NULL);
  select * from boats;
  select count(*), avg(knots), group_concat(name) from boats;
  select sqlite_version();"
```

```text
1|Aurora|6.5
2|Wind|8.0
3|Kees|NULL
3|7.25|Aurora,Wind,Kees
3.46.0
```

Here `driver.c` is `#include "sqlite3.c"` plus a `main` that opens `:memory:`
and passes its argument to `sqlite3_exec`.

zlib's own test program gives the same output as the GCC build, byte for byte:

```text
zlib version 1.3.1 = 0x1310, compile flags = 0xa9
uncompress(): hello, hello!
gzread(): hello, hello!
...
```

The repository's recipes for these are `make test-zlib`, `make test-lua` and
`make test-cjson`. Those targets build with the in-tree compiler rather than
the pin.

## A bootable minimal Linux system

This isn't a program under `examples/`, but it is built from the checkout: a
BIOS and EFI ISO carrying a stock Linux kernel, a BusyBox shell compiled by
PXX and linked with no C library, and the PXX compiler itself, which compiles
and runs programs inside the guest. See
[A minimal Linux system](./minimal-linux-system.md) for the build, what it
does and does not establish, and its limits. It was not rebuilt for this page;
its build downloads a distribution kernel.

## Next

- [Getting started](../getting-started/)
- [Standard library](../library/)
- [Targets](../targets/)
- [A minimal Linux system](./minimal-linux-system.md)
