# lekkerzeilen census — THE BASELINE, per module

tree 39eb1ad63 · binary ca814b0aabcc · 2026-09-10 · frankZ

**This file exists because a COUNT is not a baseline.** The previous census
recorded "21 clean of 35" and no list, so no delta after it could be
attributed to a module, and the 21 cannot be reconciled with today's 20 even
though the one module known to have changed went the RIGHT way. That figure
is unreliable and is not carried forward. This list is the baseline; the next
census diffs against it.

```
lekkerzeilen/app.py                        WALL   error: import: no unit named threading and no shim mimic_thr
lekkerzeilen/atlas.py                      WALL   error: no member connect came of the qualifier sqlite3 — c
lekkerzeilen/audio.py                      CLEAN  
lekkerzeilen/bindings.py                   WALL   error: no member KEY_ESCAPE came of the qualifier platform �
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

    platform/__init__.py   ctypes import wall  ->  undefined variable (_pxx)

That is **theirs**, it is the seam their ticket describes, and the clean count
is 20 on both binaries. A wall moving and a module compiling are different
claims, and this is the pair demonstrating it.

`ui.py` is clean, and its `undefined variable (MARGIN)` wall at line 1376 is
gone — that is f3cc8525a, the class-body defaults door. It is the only row
this seat can claim.

## The two crashes are ONE bug

`traffic.py:44` is `from . import vessel`, so `traffic.py` is blocked behind
`vessel.py`'s SIGSEGV rather than failing on its own. Counting them as two
walls would be the queue-position error CLAUDE.md names.
See bug-n-the-compiler-segfaults-on-lekkerzeilen-vessel-py.

## Remaining walls by cause, not by count

- **ctypes** — capture, gfx, _ctypes_backend, _gl, _sdl2 (5)
- **threading** — app, gauges, __main__ (3)
- **sqlite3.connect** — atlas, world (2)
- **platform.KEY_ESCAPE** — bindings (1)
- **os** — session (1)
- **_pxx** — platform/__init__ (1, newly here)
- **SIGSEGV** — vessel, and traffic behind it (1 bug, 2 modules)

Five of the seven are one missing shim each. **Do not rank them on how many
modules name them** — a first-failure census reports one error per subject,
so a shared import is structurally over-represented and the walls behind it
are invisible.
