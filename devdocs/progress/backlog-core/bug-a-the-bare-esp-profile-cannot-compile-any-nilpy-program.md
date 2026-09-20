---
slug: bug-a-the-bare-esp-profile-cannot-compile-any-nilpy-program
track: A
prio: 55
type: bug
status: new
created: 2026-09-20
found-by: frankS
blocked-by: []
summary: "`tools/esp_run_bare.sh --chip esp32c3 <prog.npy>` fails on EVERY NilPy program tried, including `print(1)`, with three errors inside units the compiler appends itself: `pascal26:1355: error: undefined variable (PXXVarBinOp)`, `pascal26:2029: error: undefined variable (PxxSciDigits17)` and, on a program using str()/concat, `pascal26:193: error: compiler error: PXXRecordRelease not found` in compiler/builtin/promocore.pas. The IDF profile (--platform=esp) compiles the same sources fine, so this is the BARE path specifically. Found 2026-09-20 while trying to build a sensitivity control for [[bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile]], and it BLOCKS that ticket's proof: bare is the only profile where the NilPy heap arena is actually the heap, so it is the only place a deliberately-too-small arena can be shown to fail. The absence is invisible to every tier -- test-esp-bare's fourteen rows are all Pascal, so nothing ever compiles a .npy for bare and the wall generates no red."
---

# The bare ESP profile cannot compile any NilPy program

Measured 2026-09-20, compiler at `c6c5f5f1b`, stock `SocNilPyArenaSize`.

```
$ printf 'print(1)\n' > tiny.npy
$ tools/esp_run_bare.sh --chip esp32c3 tiny.npy
pascal26:1355: error: undefined variable (PXXVarBinOp)
pascal26:2029: error: undefined variable (PxxSciDigits17)
```

With `str()` and string concatenation the program dies earlier still, inside
`compiler/builtin/promocore.pas`:

```
pascal26:193: error: compiler error: PXXRecordRelease not found
```

Every one of these is in a unit **the compiler appends itself** — the
diagnostic says so — so this is not the user program's doing.

## Why nothing caught it

`test-esp-bare`'s rows are Pascal fixtures. **Nothing anywhere compiles a
`.npy` for `--esp-profile=bare`**, so the wall produces no red and no ticket.

**This is a coverage hole that produces SILENCE, which is the shape nobody
finds by watching for reds.** A broken row goes red and someone bisects it; a
row that does not exist generates nothing at all, and the profile reads as
healthy for exactly as long as nobody tries it. It was found only because a
DIFFERENT ticket needed this profile as a control — i.e. by someone walking in
from outside, which is the only way an absence is ever found.

## Why it matters beyond itself

It **blocks the proof** of
[[bug-a-the-nilpy-heap-arena-is-64-kib-of-dead-sram-on-the-esp-idf-profile]].
That ticket's claim is that a 64 KiB arena is dead on IDF, evidenced partly by
a 16-byte arena leaving the demo passing. That evidence is only worth
something if a live 16-byte arena would fail loudly — and **bare is the only
profile where the arena is the heap**, so it is the only place that control can
be run.

It also means the arena constant currently helps nobody: it costs 64 KiB on
the profile that works and serves the profile that does not compile.

## What would retire this

A NilPy program booting under `esp_run_bare.sh` on both chips, and a row in
`test-esp-bare` that compiles a `.npy` — **the absence of which is the actual
defect here**, since the compile wall is a thing anyone could have hit and
nobody did.
