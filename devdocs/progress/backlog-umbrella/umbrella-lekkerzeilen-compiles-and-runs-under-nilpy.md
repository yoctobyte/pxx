---
slug: umbrella-lekkerzeilen-compiles-and-runs-under-nilpy
track: N
prio: 75
type: umbrella
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, corpus, real-world, lekkerzeilen]
blocked-by:
  - bug-n-a-class-body-cannot-alias-a-method-defined-above-it
  - feature-n-the-array-module
  - decide-n-does-nilpy-emulate-ctypes-or-bind-natively
  - bug-n-collections-deque-is-missing
  - bug-n-str-join-rejects-an-argument-shape-cpython-accepts
  - feature-nilpy-math-module-twelve-absent-names-measured
summary: "Owner-set target (2026-09-08): the lekkerzeilen sailing simulator -- /home/neo/lekkerzeilen, 14,297 LOC of Python, 26 runtime modules -- as a REAL-WORLD nilpy target. It was written knowing about pxx and it shows: the runtime package imports ZERO third-party libraries (numpy and PIL appear only under tests/ and tools/), there is not one f-string in it, and no async, yield, match, walrus or annotation. Measured 2026-09-08 with compiler/pascal26 at a7b03135f504: 3 of 16 runtime modules compile clean, and the other 13 fail on SIX distinct causes, one of which blocks seven modules by itself. TWO STANDING RULES FROM THE OWNER, both unusual and both deliberate: (1) WE MAY CHEAT ON THE SOURCE -- where something is principally incompatible with nilpy, changing lekkerzeilen is allowed, which is the opposite of the usual corpus rule; (2) it is NOT to be wired into the test suite, like uforth. It is a target to attempt, not a gate."
---

# What the owner said

> *"we have a new project ... i told it about pxx and to keep that in mind, so i
> think it did — not pulling in some typical python libraries etc.. but, it
> would be a good test target for us and nilpy. so, two things to note please —
> this time we are allow to 'cheat' on the code base. if there's something
> that's principally incompatible with nilpy, we could fix the source. so.. it
> just serves as a real-world testing project, and for now is not to be included
> in our test suite (like uforth)."*

**Both halves are load-bearing and both invert a normal rule, so read them before
working this.**

**CHEATING IS ALLOWED HERE.** Everywhere else a corpus is sacred: we compile
UNVENDORED upstream source precisely so the corpus cannot be bent to fit the
compiler, and bending it would destroy what the measurement is for. Not here.
lekkerzeilen is the owner's own project and he has explicitly licensed changing
it where a construct is *principally* incompatible with nilpy.

**That licence is not a licence to take the easy road, and the judgment it hands
you is the actual work.** Each blocker below is a fork: fix nilpy, or fix
lekkerzeilen. The test is whether the construct is **idiomatic Python that nilpy
ought to support** — then it is a compiler bug and the source stays — or whether
it is **incidental**, in which case changing the source is cheaper than growing
the frontend and nothing is lost. The first blocker below is squarely the former;
the ctypes one is squarely the latter. Say which fork you took and why, in the
commit.

**IT IS NOT A GATE.** Do not add it to `make test`, `test-nilpy`, or any tier.
uforth is the precedent: a real program we compile and benchmark, not a row that
can go red and block a pin. If it earns a permanent row later, that is the
owner's call and a separate ticket.

# The target

`/home/neo/lekkerzeilen` — a leisure sailing simulator, free-roam, 3D, real
geography, inland waterways first. Its own README states the constraint that
makes it interesting to us:

> *"**Plain Python, no C extensions** — SDL2 and OpenGL are bound directly, so
> the same source can eventually compile under PXX. No asset files either ...
> because a sample library would mean a decoder and a decoder would mean a C
> extension."*

So the pxx constraint is already designed in, by the owner, before we touched it.
That is why the numbers below are as good as they are.

**It is under active development** — files changed during this very census — so
every count here is dated, not current. Re-measure before quoting.

# What it is made of (measured 2026-09-08, `ast`, not grep)

| | |
| --- | --- |
| Python | 14,297 LOC, 45 files, all parse clean under CPython 3.14 |
| runtime package `lekkerzeilen/` | 26 files, 58 classes, 429 functions |
| **third-party imports in the runtime package** | **zero** |
| numpy / PIL | `tests/` (3) and `tools/` (1) only — dev-side, not the simulator |
| stdlib used | math, ctypes, struct, array, sys, os, time, sqlite3, io, json, urllib, zlib, collections, argparse, warnings, shutil |
| f-strings | **0** — formats with `%` at 90 sites |
| async / await / yield / match / walrus / nonlocal | **0 of each** |
| type annotations | **0** of 1074 arguments |
| decorators | `property` (41), `staticmethod` (15), `classmethod` (2), 2 setters — nothing else |
| uses | classes, comprehensions (21 genexp, 20 listcomp), `try` (15), `with` (4), starred (32), `global` (3) |

**A first-error census is a LOWER BOUND, not a work estimate.** The compiler
stops at the first error in a module, so each row below names *the cause that was
hit first*, not every cause present. Expect more behind each one. The one thing
it does establish is which cause blocks the most modules today.

# The blockers, in the order attempting the target found them

Measured with `compiler/pascal26` sha256 `a7b03135f504`, built 2026-09-08 13:05.
**3 of 16 compile clean today: `geometry`, `scenery`, `shaders`.**

**1. A class-body assignment cannot reference a method defined in that same class
body — blocks SEVEN modules through one line.** `math3d.py:54` is
`__rmul__ = __mul__`, and every module that imports `math3d` inherits the failure
(math3d, wind, rig, vessel, sim, traffic, app). The diagnostic
`undefined variable (__mul__)` reads as "operator overloading is unsupported",
and **that reading is wrong** — nilpy knows `__mul__`, `__add__`, `__sub__`,
`__truediv__`, `__neg__`, `__eq__` and more. What it does not do is expose an
already-defined method as an ordinary NAME in the class namespace. Minimal repro,
with the positive control that separates the two readings:

```python
class V:
    def __init__(self, x): self.x = x
    def __mul__(self, s):  return V(self.x * s)
    __rmul__ = __mul__          # <-- pascal26: undefined variable (__mul__)
v = V(3) * 4
print(v.x)                      # CPython: 12
```

Delete the alias line and the identical class compiles and prints `12`, matching
CPython. **Fork: fix nilpy.** `name = earlier_name` in a class body is ordinary
Python and the `__rmul__ = __mul__` idiom is how every vector class in the
language is written; the source should not move for this.

**2. `array` is not available — 2 modules** (`world`, `audio`).
`import: no unit named array and no shim mimic_array`. The shim naming suggests
the mechanism exists and this module has not been written.

**3. `ctypes` is not available — 1 module, and it is the whole platform layer**
(`gfx`; also `platform/_ctypes_backend.py`, `_sdl2.py`, `_gl.py`). `ctypes` gets
**zero** hits anywhere in `pyparser.inc`/`pylexer.inc`. This is the one genuinely
large item and the one where the cheat licence most plausibly applies: binding
SDL2 and OpenGL through a pxx-native mechanism instead of emulating CPython's
`ctypes` may be far cheaper and is arguably the better artefact. **This is a
Track U-shaped fork, not a bug — do not start building `mimic_ctypes` without
settling it.**

**4. `collections.deque` — 1 module** (`chart`).

**5. `math.atan2` — 1 module** (`hud`), **and it is a DELIBERATE refusal, not a
gap.** `atan2` is measured 1 ulp off, and the standing policy is to keep a
1-ulp-off RTL routine out rather than trade a loud `undefined variable` for a
silently wrong last digit — see `feature-nilpy-math-module-twelve-absent-names-measured`,
which owns it and is blocked on the correctly-rounded-libm work. **Do not "fix"
this with a table row**; that is the fix the project has refused twice, and this
seat proposed it before reading far enough. **This is the clearest place the
cheat licence applies:** the refusal governs what `math.atan2` may silently mean
for every program, not whether this one may call `ArcTan2` knowingly. A HUD
heading does not care about the last digit.

**6. `str.join` overload — 1 module** (`text`):
`no overload of join matches these arguments`.

# Why this target is worth its rank

Every existing nilpy corpus proves one layer. This is 14k lines of ordinary,
idiomatic, third-party-free Python written by someone who was not trying to
exercise a compiler — which is exactly the population our fixtures cannot draw
from. It is also **interactive and graphical**, so it reaches the FFI, the float
paths and the real-time loop rather than a batch pipeline.

And it is a fair test of NilPy's stated direction: NilPy is *upward* compatible
with CPython, one direction, so a program written in plain Python with no
cleverness is precisely what must work.

# Provenance and one caveat on the path

Filed after attempting the target, which is how CLAUDE.md says to grow an
umbrella — every blocker above is a real failure of a real compile, not a triage
of the backlog.

**The owner named the project `~/marine`. There is no `~/marine` on plexus or on
seven**, and this ticket is about `/home/neo/lekkerzeilen`, which matches his
description (marine, new, Python, told about pxx) and whose README names pxx
explicitly. If he meant a different tree, this ticket is about the wrong one.
