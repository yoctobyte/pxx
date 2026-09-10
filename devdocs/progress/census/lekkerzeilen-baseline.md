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

## DIFF 1 — binary 84993c095465, 2026-09-10, frankZ

The first census diffed against this baseline, which is what the file was for.

**CLEAN 20 → 21 · CRASH 2 → 0 · WALL 13 → 14 of 35.**

**Expectation recorded BEFORE the re-run**, and matched exactly: two rows move,
33 unchanged. `vessel.py` CRASH → CLEAN; `traffic.py` CRASH → WALL. The
prediction was checkable because only `Vessel.__init__` has ≥17 parameters
anywhere in the package — every other module was untouched by the fix and had
to stay put, and did.

**"The two crashes are ONE bug" is confirmed, and by the fix rather than by the
argument.** `traffic.py` contains no method with ≥17 parameters; it inherited
the crash through `from . import vessel` alone. Fixing `vessel.py` moved it
without a line of `traffic.py` changing. The fan-in reading was right.

**A crash was hiding a wall.** `traffic.py` now fails on
`cannot infer the type of field self.heading - annotate it` — a diagnostic that
was always there and unreachable behind the segfault. So CRASH → WALL is
progress even though the module still does not compile, and the WALL count
going UP by one is not a regression. A census that ranked on wall count alone
would read this diff as flat-to-worse.

Walls by cause, updated — the SIGSEGV row is gone and a type-inference row
takes its place:

- **ctypes** — capture, gfx, _ctypes_backend, _gl, _sdl2 (5)
- **threading** — app, gauges, __main__ (3)
- **sqlite3.connect** — atlas, world (2)
- **platform.KEY_ESCAPE** — bindings (1)
- **os** — session (1)
- **_pxx** — platform/__init__ (1)
- **field type inference** — traffic (1, newly visible)

**Population note:** the owner edited `lekkerzeilen/app.py` at 20:32 during this
work, after the baseline copy was taken. `app.py` is walled on `threading` in
both runs, so nothing here is attributable to that — but the corpus is LIVE and
moved under the instrument once already today. Record the repo's dirty state
with any future census; this run's harness prints it.

## THE CASCADE THAT THE COUNT HID — frankB, 2026-09-10

Recorded as frankB's measurement, not re-derived here: it needs a binary from
before the owner's `f98fd53d7` and the point does not depend on the digits.

`f98fd53d7` (owner, 15:34) replaced a flat refusal of `*unpacking into a
constructor with defaulted parameters` with a run-time-length expansion. **Five
modules were walled on that refusal.** Three — `rig`, `sim`, `ui` — went green.
The other two — `vessel`, `traffic` — cleared it and **advanced into the
method-parameter SIGSEGV**, which is what put them in this baseline as CRASH.

So one fix delivered its ENTIRE population to the next wall, and two thirds of
that population landed on the next seat's defect. This is CLAUDE.md's
`cclasses.pas` finding — three walls in one file, each fix handing its whole
population to the next a few hundred lines on — reproducing on a second corpus
with no code in common.

**It is visible only because this file keeps a per-module list.** A count would
have reported +3 clean and concealed both the cascade and the fact that the
remaining two had moved at all. That is the argument for the list, made by an
event rather than by assertion.

## SAME-LINE-NUMBER CASCADES IN THIS CORPUS — six instances now

An error raised inside an IMPORTED module prints as `pascal26:<n>:` with THAT
module's line number and no file name, so the reader supplies the file they
invoked. Every instance found in this corpus, three of them frankB's:

- `vessel` / `traffic` — one SIGSEGV, two subjects, via `from . import vessel`.
  `traffic.py` has no method with ≥17 parameters at all.
- `atlas` / `world` — both report `:188 no member connect ... sqlite3`.
  `atlas.py:188` is `if box is None:`, with no sqlite3 within a hundred lines.
  It is `world.py:188`, through `from . import world`. One site, two subjects.
- `__main__` / `gauges` — both report `:36 no unit named threading`.
  `gauges.py:36` genuinely is `import threading`; **`__main__.py:36` is a blank
  line.** Two real threading sites in the corpus (`app.py:15`, `gauges.py:36`),
  three modules reported.
- `bindings` — downstream of `platform/__init__` rather than a site of its own.

**So of the walls in this census, the number of distinct CAUSES is materially
smaller than the number of walled modules**, and the gap is not visible from the
error text. Grep the subject for the construct before ranking anything on how
many modules name it.
