---
track: B
prio: 40
type: bug
blocked-by: []
summary: "examples/mandelbrot/mandelbrot_gui.pas calls gtk_main_quit but does not `uses gtk3_c`, the C header that declares it — so `make demos` builds 34/35. Its two sibling GUI demos both use it. Verified one-line fix: adding gtk3_c to the uses clause builds the program clean."
status: done
owner: frank3
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

## 2026-08-17 — FIXED (Track B, frank3)

`examples/mandelbrot/mandelbrot_gui.pas` now reads

```pascal
uses gtk3, controls, stdctrls, forms, extctrls, graphics, math, sysutils, baseunix,
     palparallel, mandelkernel, gtk3_c;
```

which is exactly what `raytracer_gui.pas` and `solitaire_gui.pas` already do.

### Verified

| check | result |
| --- | --- |
| `make demos` | **35/35** (was 34/35) |
| `./build/demos/mandelbrot_gui --smoke` | renders, `serial == parallel — OK`, checksum 4883296 |
| `./build/demos/mandelbrot_gui --gui-smoke` | `GUI SMOKE OK`, exit 0 |
| `make lib-test` | green against stable v344 |

`--gui-smoke` matters here specifically: `GuiAutoQuit` is the *only* caller of
`gtk_main_quit`, so that run exercises the symbol the missing import broke,
under a real X display and a real event loop. It quits cleanly.

### On the ticket's open question — should `gtk3.pas` re-export the symbol?

**No, and it cannot.** `lib/pcl/gtk3.pas` already has `uses gtk3_c` in its
*interface*, and the symbol still is not visible to a program that uses `gtk3`
— because Pascal units do not re-export their imports transitively (FPC behaves
the same way). There is no `exports`-style spelling that would forward
`gtk_main_quit` without hand-writing a wrapper for it and every other GTK entry
point a demo might reach for, which is the opposite of what a *thin* binding is
for.

So "three demos need a C header for one symbol" is not an incomplete binding —
it is the binding working as designed: `gtk3.pas` exists to add the three things
C cannot express (`SignalConnect`, `SignalConnectData`, `PC`), and everything
else comes straight from `gtk3_c.h`. Naming both in `uses` is the intended
idiom, and the two sibling demos are the precedent. Nothing further to file.

### Environment note (not part of the fix)

`make lib-test` first failed in this checkout at `lib_synapse` with
`unit source not found: synacode` — `external/synapse` is an untracked
third-party tree with no fetch rule in the Makefile, so a fresh clone simply
does not have it. Copied from a sibling checkout; unrelated to this ticket, but
it is a real papercut for any new checkout.

## Log
- 2026-08-17 — resolved, commit PENDING-COMMIT.
