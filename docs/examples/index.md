---
title: Examples
order: 55
---

# Examples

The checkout includes example programs under `examples/`. They are useful for
learning the language surface, checking library behavior, and exercising larger
application shapes than a single hello-world file.

Run the example launcher after installation:

```sh
./install.sh
./demos.sh list
./demos.sh all
```

`./demos.sh all` builds and runs the batch demos. Interactive and GUI demos are
listed but are not run automatically by the batch mode.

## Batch demos

| Name | Source | Shows |
| --- | --- | --- |
| `primes` | `examples/primes/sieve.pas` | Sieve of Eratosthenes. |
| `sudoku` | `examples/sudoku/sudoku.pas` | Backtracking solver. |
| `factorial` | `examples/bignum/factorial.pas` | Big-integer factorial. |
| `bigmath` | `examples/bignum/bigmath.pas` | Arbitrary-precision arithmetic. |
| `json` | `examples/json/jsondemo.pas` | JSON parse and emit. |
| `sat` | `examples/sat/satdemo.pas` | DPLL SAT solver. |
| `mathf` | `examples/mathf/mathdemo.pas` | Floating-point math helpers. |
| `maze` | `examples/maze/maze.pas` | Maze generation. |
| `mandelbrot` | `examples/mandelbrot/mandelbrot.pas` | ASCII Mandelbrot output and interactive TUI explorer. |
| `vm` | `examples/vm/vmdemo.pas` | Tiny bytecode VM. |

Build one directly:

```sh
./pxx examples/json/jsondemo.pas /tmp/jsondemo
/tmp/jsondemo
```

## Interactive terminal demos

| Name | Source | Shows |
| --- | --- | --- |
| `life` | `examples/life/life.pas` | Terminal animation. |
| `calc` | `examples/calc/calcdemo.pas` | Expression calculator. |
| `lisp` | `examples/lisp/lispdemo.pas` | Small REPL. |
| `chess` | `examples/chess/chess.pas` | Console engine. |
| `adventure` | `examples/adventure/adventure.pas` | Text adventure. |
| `2048` | `examples/g2048/console_2048.pas` | Terminal game. |
| `solitaire` | `examples/solitaire/console_solitaire.pas` | Terminal card game. |
| `menu` | `examples/tui/menudemo.pas` | Terminal UI widgets. |

Run these through the launcher so the terminal interaction is clear:

```sh
./demos.sh
```

## GUI demos

GUI demos need the relevant desktop libraries and a display server. The launcher
builds them and prints the generated executable path instead of launching every
GUI program automatically.

| Name | Source | Shows |
| --- | --- | --- |
| `triangle` | `examples/gl/triangle.pas` | OpenGL setup. |
| `solitaire-gui` | `examples/solitaire_gui/solitaire_gui.pas` | GUI card-game surface. |
| `fm` | `examples/fm/fm.pas` | GTK file manager. |
| `player` | `examples/player/player.pas` | GTK media-player shell. |

## Networking demo

The networking demo has its own notes in `examples/net/README.md`. It runs a
loopback HTTP server and client on one coroutine reactor thread, so it does not
need an external network service:

```sh
./pxx examples/net/httpdemo.pas /tmp/httpdemo
/tmp/httpdemo
```

## Next

- [Getting started](../getting-started/)
- [Standard library](../library/)
- [Targets](../targets/)
