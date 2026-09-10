# lekkerzeilen census — THE BASELINE, per module

tree 39eb1ad63 · binary ca814b0aabcc · 2026-09-10 · frankZ

**This file exists because a COUNT is not a baseline.** The previous census
recorded a bare "21 clean" and no list, so no delta after it could be
attributed to a module. This list is the baseline; the next census diffs
against it.

## The old figure, RECONCILED rather than discarded

The earlier number was **21 clean of 29**, and two things said about it in
passing are both wrong. Correcting them here rather than leaving them in
message history for the next reader to find and reuse.

**It was not a different module SET.** The 29 is exactly `lekkerzeilen/*.py`
before `atlas.py` existed — top level only, missing `lekkerzeilen/platform/*.py`
because the glob never descended. Restricting today's census to that same set
gives **29 modules, 19 clean**, which confirms the identification: the old set
IS a subset of this one.

**And `platform/` never "moved under `lekkerzeilen/`".** `git log --diff-filter=A`
puts `lekkerzeilen/platform/__init__.py` in the repo's INITIAL commit. It was
always there; the old census simply did not look in it. A claim about a file
move was made from the shape of a count and was checkable in one command.

So the corpus went 29 → 35 by **+1 `atlas.py`** and **+5 `platform/`** — all
additions, nothing removed or relocated.

### What the reconciliation shows

On the SAME 29 modules: 21 clean then, **19 clean now**. The shape accounts
for it and needs no regression:

- `ui.py` went clean — **+1** (`f3cc8525a`, the class-body defaults door)
- `vessel.py` now SIGSEGVs and `traffic.py` is blocked behind it — **-2**

Net -1, so 20 → 19. The recorded figure was **21, one higher than the shape
supports**, and that last unit cannot be chased because the old census kept no
list. That is the argument for this file, and better evidence for it than
"the number is unreliable" would have been.

**NOT established:** the crash predates 2026-09-10 (it reproduces on
`f45ed34d4012`), but nobody has shown it predates `1266f201c140`, the binary the
old census ran on. If it was introduced in between, part of the -2 is a
regression in a narrow window. Open question in the ticket, not answered here.

## The list

```
lekkerzeilen/app.py                        WALL   error: import: no unit named threading and no shim mimic_thr
lekkerzeilen/atlas.py                      WALL   error: no member connect came of the qualifier sqlite3 — c
lekkerzeilen/audio.py                      CLEAN  
lekkerzeilen/bindings.py                   WALL   error: no member KEY_ESCAPE came of the qualifier platform
lekkerzeilen/capture.py                    WALL   error: import: no unit named ctypes and no shim mimic_ctypes
lekkerzeilen/chart.py                      CLEAN  
lekkerzeilen/drone.py                      CLEAN  
lekkerzeilen/environment.py                CLEAN  
lekkerzeilen/figure.py                     CLEAN  
lekkerzeilen/gauges.py                     WALL   error: import: no unit named threading and no shim mimic_thr
lekkerzeilen/geometry.py                   CLEAN  
lekkerzeilen/gfx.py                        WALL   error: import: no unit named ctypes and no shim mimic_ctypes
lekkerzeilen/hud.py                        CLEAN  
lekkerzeilen/__init__.py                   CLEAN  
lekkerzeilen/lines.py                      CLEAN  
lekkerzeilen/__main__.py                   WALL   error: import: no unit named threading and no shim mimic_thr
lekkerzeilen/math3d.py                     CLEAN  
lekkerzeilen/platform/_ctypes_backend.py   WALL   error: import: no unit named ctypes and no shim mimic_ctypes
lekkerzeilen/platform/_gl.py               WALL   error: import: no unit named ctypes and no shim mimic_ctypes
lekkerzeilen/platform/__init__.py          WALL   error: undefined variable (_pxx)
lekkerzeilen/platform/_pxx.py              CLEAN  
lekkerzeilen/platform/_sdl2.py             WALL   error: import: no unit named ctypes and no shim mimic_ctypes
lekkerzeilen/rd.py                         CLEAN  
lekkerzeilen/rig.py                        CLEAN  
lekkerzeilen/scenery.py                    CLEAN  
lekkerzeilen/session.py                    WALL   error: undefined variable (os)
lekkerzeilen/shaders.py                    CLEAN  
lekkerzeilen/sim.py                        CLEAN  
lekkerzeilen/text.py                       CLEAN  
lekkerzeilen/traffic.py                    CRASH  
lekkerzeilen/ui.py                         CLEAN  
lekkerzeilen/vessel.py                     CRASH  
lekkerzeilen/wake.py                       CLEAN  
lekkerzeilen/wind.py                       CLEAN  
lekkerzeilen/world.py                      WALL   error: no member connect came of the qualifier sqlite3 — c
```

CLEAN 20 · CRASH 2 · WALL 13 · total 35

## Attribution of what moved since binary 2255ecda014c

Exactly one commit touches `compiler/` or `lib/rtl/` in bdff4d22d..39eb1ad63:
frankB's `708555fdb`. Exactly one row moved:

    platform/__init__.py   ctypes import wall  →  undefined variable (_pxx)

That is **theirs**, it is the seam their ticket describes, and the clean count
is 20 on both binaries. A wall moving and a module compiling are different
claims, and this is the pair demonstrating it: a census reporting only the
count would have shown their change as nothing at all.

`ui.py` is clean and its `undefined variable (MARGIN)` wall at line 1376 is
gone — `f3cc8525a`. The only row this seat can claim.

## The two crashes are ONE bug

`traffic.py:44` is `from . import vessel`, so `traffic.py` is blocked behind
`vessel.py`'s SIGSEGV rather than failing on its own. Counting them as two
walls would be the queue-position error in its purest form — a fan-in
inflating a number. See bug-n-the-compiler-segfaults-on-lekkerzeilen-vessel-py.

## Remaining walls by cause, not by count

- **ctypes** — capture, gfx, _ctypes_backend, _gl, _sdl2 (5)
- **threading** — app, gauges, __main__ (3)
- **sqlite3.connect** — atlas, world (2)
- **platform.KEY_ESCAPE** — bindings (1)
- **os** — session (1)
- **_pxx** — platform/__init__ (1, newly here)
- **SIGSEGV** — vessel, and traffic behind it (1 bug, 2 modules)

Five of the seven are one missing shim each. **Do not rank them on how many
modules name them** — a first-failure census reports one error per subject, so
a shared import is structurally over-represented and the walls behind it are
invisible.
