---
track: B
prio: 40
type: bug
blocked-by: []
summary: "examples/mandelbrot/mandelbrot_gui.pas calls gtk_main_quit but does not `uses gtk3_c`, the C header that declares it — so `make demos` builds 34/35. Its two sibling GUI demos both use it. Verified one-line fix: adding gtk3_c to the uses clause builds the program clean."
---

# `mandelbrot_gui` does not build — `gtk_main_quit` with no `gtk3_c`

- **Type:** bug (example app — Track E, file-owned by **Track B**)
- **Opened:** 2026-08-17
- **Found by:** Track T, on the first run of the newly-enrolled advisory `demos`
  job ([[task-t-enroll-libtest-demos-watcher]]). T owns the tool, never the bug.

## Symptom

```
make demos
  FAIL  examples/mandelbrot/mandelbrot_gui.pas
  === demos: 34/35 built into build/demos/ (esp32 skipped — cross-only) ===
```

The error, with the recipe's own flags (`--threadsafe`, the auto-discovered
`-Fu` set, `-Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix`):

```
pascal26:213: error: undefined variable (gtk_main_quit)
  near: writeln  GUI SMOKE OK   gtk_main_quit >>>  GuiAutoQuit
```

## Cause

`gtk_main_quit` is declared in **`lib/pcl/gtk3_c.h`** — a C header, reached by
`uses gtk3_c`, not by `uses gtk3`. `lib/pcl/gtk3.pas` (the unit actually on the
`-Fu` path) does not declare it; the only Pascal declaration lives in
`lib/pcl/historic/gtk3.pas`, which is **not** on the demos search path.

Of the three GUI demos that call it, mandelbrot is the only one missing the
import:

| demo | `uses gtk3_c` | builds |
| --- | --- | --- |
| `raytracer_gui.pas` | yes | yes |
| `solitaire_gui.pas` | yes | yes |
| **`mandelbrot_gui.pas`** | **no** | **no** |

## Fix, verified

Add `gtk3_c` to the uses clause:

```pascal
uses gtk3, controls, stdctrls, forms, extctrls, graphics, math, sysutils, baseunix,
     palparallel, mandelkernel, gtk3_c;
```

Compiled against the pinned binary with the recipe's exact flags:

```
ok: mg_test  [code=453850B  data=67504B  bss=49300B  procs=1335]
```

Track T does not land it — `examples/**` is Track B's file ownership, and a demo
that has been broken since it landed may want its author's eye on whether
`gtk3_c` is the intended import or whether `lib/pcl/gtk3.pas` should re-export
`gtk_main_quit` (three demos needing a C header for one symbol is a smell that
the Pascal binding is incomplete). Either way the one-liner above is a correct
unblock.

## Two false trails, recorded so the next person skips them

1. **The first repro was wrong and produced a different error.** Compiling
   without `--threadsafe` gives `__pxxclone (thread creation) requires
   --threadsafe`, which looks like the bug and is not — the recipe derives that
   flag from a `palparallel` grep, and this source does use it. **Reproduce with
   the recipe's flags, not a simplified command line.**
2. **`gtk3_c` is not a Pascal unit and `find -name 'gtk3_c.pas'` finds nothing.**
   It is a `.h`. Searching for a missing *unit* dead-ends; the symbol is in a C
   header reached through the same `uses`.

## Why it went unnoticed

`make demos` ends `exit 0` by design — *"demos is a dashboard, not a gate; FAILs
-> file a ticket"* — and until 2026-08-17 nothing enrolled it, so the FAIL line
was only ever seen by whoever happened to run it and read the output. It is now
an ADVISORY tstate job: reported to Track B, gating nobody, which is the status
the recipe itself assigns it.
