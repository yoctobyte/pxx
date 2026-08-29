---
prio: 40
track: T
---

> **Track T by default: no lane could be inferred** (the job reported no test source). This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 32 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# advisory: demos#00 red at b26e7ed366f3 (auto-filed by twatch)

- **Type:** advisory (NOT a gate — nothing day-to-day depends on this path; a notice for the owning track) (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T21:17:12Z
- **Test source:** unknown (see repro commands)

## Repro
`tools/testmgr.py --tier full --job 'demos#00'` at b26e7ed366f37d1df21bb8595fc2c0d462db0949

## Range
> **The named sha `b26e7ed366f3` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `b26e7ed366f3`, last good `9beb2af4946c`, **20 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (8 src) -- isolates track A's compiler/builtin/ edits
=== demos: build ALL examples/* against stable_linux_amd64/default/pinned into build/demos/ ===
  FAIL  examples/adventure/adventure.pas  --   near: end  end  if PngDecodeRGBA >>>  bytes  
  OK    examples/bignum/bigmath.pas
  OK    examples/bignum/factorial.pas
  OK    examples/calc/calcdemo.pas
  OK    examples/chess/chess.pas
  FAIL  examples/fm/fm.pas  --   near:  then Exit  if PngDecodeRGBA >>>  bytes  
  OK    examples/g2048/console_2048.pas
  OK    examples/gl/triangle.pas
  OK    examples/hello/hello.pas
  OK    examples/json/jsondemo.pas
  OK    examples/life/life.pas
  OK    examples/lisp/lispdemo.pas
  OK    examples/mandelbrot/mandelbrot_gui.pas
  OK    examples/mandelbrot/mandelbrot_parallel.pas
  OK    examples/mandelbrot/mandelbrot.pas
  OK    examples/mandelbrot/mandelzoom.pas
  OK    examples/mathf/mathdemo.pas
  OK    examples/maze/maze.pas
  OK    examples/net/httpdemo.pas
  OK    examples/parallel/collatz.pas
  OK    examples/parallel/membw.pas
  OK    examples/parallel/pow.pas
  OK    examples/parallel/primecount.pas
  OK    examples/player/player.pas
  OK    examples/primes/sieve.pas
  OK    examples/raytracer/raytracer_gui.pas
  FAIL  examples/raytracer/raytracer.pas  --   near: bytes  TByteArray  begin PngEncodeRGBA >>>  img  
  OK    examples/sat/satdemo.pas
  OK    examples/solitaire/console_solitaire.pas
  OK    examples/solitaire_gui/solitaire_gui.pas
  OK    examples/sudoku/sudoku_game.pas
  OK    examples/sudoku/sudoku.pas
  OK    examples/tk/uses_tkinter_and_configparser.pas
  OK    examples/tui/menudemo.pas
  OK    examples/vm/vmdemo.pas
=== demos: 32/35 built into build/demos/ (esp32 skipped — cross-only) ===
(demos is a dashboard, not a gate; FAILs -> file a ticket)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
