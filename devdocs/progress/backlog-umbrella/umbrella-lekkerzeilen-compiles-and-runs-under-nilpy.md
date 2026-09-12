---
slug: umbrella-lekkerzeilen-compiles-and-runs-under-nilpy
track: N
prio: 90
type: umbrella
status: backlog
owner: ""
created: 2026-09-08
found-by: frankuser
tags: [nilpy, corpus, real-world, lekkerzeilen]
blocked-by:
  - task-b-write-the-lekkerzeilen-pxx-platform-backend
  - feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments
  - feature-nilpy-math-module-twelve-absent-names-measured
  - bug-n-os-environ-and-os-sep-are-not-values
  - bug-n-a-module-bound-by-an-import-is-not-a-value
  - feature-n-a-method-call-cannot-take-an-argument-after-a-star-unpack
  - bug-n-a-dict-field-resolves-pop-against-a-list-or-deque-overload-set
  - bug-nilpy-an-extended-slice-cannot-be-assigned
summary: "2026-09-12, LATER: TWO MORE WALLS CLEARED AND THE CLOSURE HAS MOVED 1120 LINES TONIGHT (app.py:1240 -> 1678 -> 2360). CURRENT WALL: app.py:2360, `assigning to an extended slice (with a step) is not implemented` -- an ALREADY-FILED ticket, bug-nilpy-an-extended-slice-cannot-be-assigned, found by a pydiff sweep on 2026-08-16 and sitting at prio 30; it is now wired here and inherits effective_prio, which is the ranker working as designed. The diagnostic is honest and precise, so it is a missing FEATURE, not a misresolution. The pop wall before it (`TPyDeque.pop() takes exactly 0 argument(s), got 2` on a dict field) was NOT the scan-order bug its ticket predicted: arFits and the arity promotion beside it asked the same question with different tests, so an overload-only match suppressed the run-time deferral and promoted nothing. SEVEN reductions of it failed and no regression fixture exists -- the closest passes pre-fix too, so committing it would be a guard that cannot fail; verification is this closure. One live bug found while reducing, filed separately: `collections.deque()` compiles and SEGFAULTS (p70). SUPERSEDED LEAD, earlier 2026-09-12: THE STAR-FOLLOWER WALL IS CLEARED AND THE CLOSURE MOVED 438 LINES FURTHER INTO app.py. A KEYWORD argument after a `*` unpack now works at all three METHOD sites; the fix was not the index-split the p75 ticket predicted but a CAP -- the compile-time expander was greedy (`wanted := ParamCount - firstSlot`, every remaining slot), and a keyword names its own slot, so stopping the star at the lowest slot a trailing `name=` claims is the whole change. CURRENT WALL: `tile.grids.pop(name, None)` refused with `pop() takes exactly 0 argument(s), got 2` -- a dict field resolved against a list's or deque's overload set, filed as bug-n-a-dict-field-resolves-pop-against-a-list-or-deque-overload-set (p80). FOUR REDUCTIONS OF IT FAILED; the ticket lists them so nobody repeats them, and says the next step is an INSTRUMENT (the arity error does not name the receiver class) rather than a fifth reduction. Still refused and separately ticketed: a trailing POSITIONAL after a star (needs the run-time length), and the CONSTRUCTOR arm of the keyword fix (its loop resolves a keyword to a FIELD index, not a parameter slot). SUPERSEDED LEAD, 2026-09-11: WALL NOW FULLY DIAGNOSED AND FILED as feature-n-a-method-call-cannot-take-an-argument-after-a-star-unpack (p75): the SAME star-plus-trailing-argument shapes work on a free function and are refused on a method, because plain calls route to the run-time forwarder and the three method sites still use the compile-time expansion that claims every remaining slot. LATE 2026-09-11: the closure now fails on `an argument after *unpacking is not supported yet` in app.py -- a KEYWORD argument after a `*` unpack, `f(*self.start[:2], forced=...)`, a shape feature-n-a-call-cannot-unpack-a-sequence-into-its-arguments did not cover and which is now the only thing between this umbrella and a compiling entry point, as far as a first-failure instrument can see. FOUR WALLS CLEARED IN ONE EVENING: ctypes in capture.py (corpus seam rewrite, uncommitted in /home/neo/lekkerzeilen); `world.label(...)` (55981bc63, f004e408e -- a unit-qualified member named like a Pascal reserved word); `import threading` (no code, just the --threadsafe flag its own diagnostic prescribes); and the type-widening refusal in App.open_region, which was NOT the conditional it appeared to be but `world.open(...)` being typed by fcntl.h's C `int open(...)` instead of world.py's own -- found only after the diagnostic was taught to print tyInt32 instead of 11. Still REQUIRES --threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES; without the two defines you get a bogus avx512fintrin.h/MAX_PROC_PARAMS error that is not the real wall. DO NOT QUOTE AN app.py LINE NUMBER -- the owner edits it live; it moved 1195 -> 1217 -> 1233 -> 1240 in one evening. PREVIOUS LEAD, 2026-09-11 evening, SUPERSEDED: `pascal26 --threadsafe -dSDL_DISABLE_IMMINTRIN_H -dGL_GLEXT_PROTOTYPES lekkerzeilen/__main__.py` now walls inside app.py's App.open_region: `annotate the type / too dynamic [a=11 b=22]` (tyInt32 vs tyVariant) on `self.world = scene if isinstance(scene, world.World) else None`, filed as bug-n-a-field-assigned-a-class-or-none-in-two-methods-wont-widen and NOT YET REDUCED -- the identical construct on the same field compiles ~600 lines earlier in the ctor, and four reductions all pass. THREE WALLS CLEARED THAT EVENING: the ctypes wall in capture.py (corpus seam rewrite, deliberately uncommitted in /home/neo/lekkerzeilen); `world.label(...)`, which was a COMPILER bug and not a corpus one (55981bc63 -- a unit-qualified member named like a Pascal reserved word was rewritten to a trailing-underscore spelling no Python module declares, so it missed by construction; f004e408e did the class sibling); and `import threading`, which needed no code at all, only the --threadsafe flag its own diagnostic prescribes. The two -d defines are required for the native backend's C headers and are not optional. DO NOT QUOTE AN app.py LINE NUMBER -- the owner edits that file live and the wall moved 1195 -> 1217 within an hour. SUPERSEDED LEAD, 2026-09-11 morning: THE ENTRY-POINT CLOSURE IS ONE WALL FROM COMPILING, measured 2026-09-11 at 7958322f8 / binary 465845b20d1e: `pascal26 --threadsafe lekkerzeilen/__main__.py` emits 27 lines and EXACTLY ONE error, `capture.py:44 no member create_string_buffer came of the qualifier ctypes`. The 28-of-35 ratio below counts modules AS SUBJECTS and includes dead code (nothing imports gfx.py; four of the five ctypes files sit in a backend arm pxx never takes) -- the closure is goal 4's question and the ratio is not. Behind that line, measured in a scratch copy, the next wall is one line further (`gl.ReadPixels`, 7 args against the 4-arg run-time-dispatch cap, filed as feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments) and BOTH WALLS ARE THE SAME CAUSE: `_pxx.py`'s `class gl:` declares five names and neither of these, so writing the backend clears both at once. AND THE FORK IS NARROWER THAN STATED BELOW -- THE DEMO NEEDS NO FFI. capture.py names ctypes for one thing, a writable byte buffer for glReadPixels read back via .raw, and the owner's own `_pxx.py` docstring specifies the native backend as having 'no CDLL loading, no restype/argtypes declarations, no create_string_buffer'. So goal 4 waits on task-b-write-the-lekkerzeilen-pxx-platform-backend, not on a ctypes decision; the FFI question is real for other programs and is not this umbrella's. The seam's probe is CORRECT (verified: `try: import ctypes / except ImportError` takes the except arm under pxx), so do NOT shim one member to clear the line -- that flips the probe, which is the 27 -> 25 measurement below. PREVIOUS LEAD, still accurate as a module ratio: RE-MEASURED 2026-09-11 at compiler f9fb672ee109 / corpus 2a3d60e: **28 of 35 compile and CTYPES IS THE ONLY WALL LEFT** -- all seven remaining failures are it. Every count and cause-list later in this summary is from 2026-09-10 and is SUPERSEDED; they are kept because the per-module reasoning is still the best record of how each wall was characterised. What cleared since: the `_pxx` module-as-a-value wall (frankZ's getattr-over-a-unit-alias fold plus frankuser's corpus seam rewrite), heapq (frankuser), and the import-order arity refusal on `nearest` (frankB, 8de1fff93, which took hud.py and traffic.py). threading and sqlite3 no longer appear as walls under `--threadsafe`. SO GOAL 4 NOW REDUCES TO ONE QUESTION AND IT IS NOT A COMPILER QUESTION: do we want NilPy programs to be able to call a native library the way CPython programs do, or do we want this app to reach the native layer through pxx's own binding mechanism and change its source to suit? The umbrella already answers it one way at 'do not build mimic_ctypes for this target' below, and frankuser MEASURED the cost of the other way on 2026-09-11: a correct partial mimic_ctypes moved the census 27 -> 25, because `import ctypes` succeeding IS A CAPABILITY PROBE -- the app's seam commits to the arm that needs the full FFI the moment the import resolves, so a partial shim is not partial progress. Owner-set target (2026-09-08): the lekkerzeilen sailing simulator -- /home/neo/lekkerzeilen -- as a REAL-WORLD nilpy target. It was written knowing about pxx and it shows: the runtime package imports ZERO third-party libraries (numpy and PIL appear only under tests/ and tools/), there is not one f-string in it, and no async, yield, match, walrus or annotation. RE-MEASURED 2026-09-10 at compiler a812b9549413, tree 813c99cc7: 22 of 35 modules compile clean. THE CORPUS MOVES UNDER YOU -- the owner renamed flight.py to drone.py at 15:47 and added atlas.py at 16:30 the same day, so it was 34 modules that morning and a delta between two censuses is not attributable to compiler work unless you check. The 13 remaining walls are FIVE causes, and THREE OF THE THIRTEEN ARE BY DESIGN AND OWE THE COMPILER NOTHING: platform/{_ctypes_backend,_gl,_sdl2} are the CPython arm of the app's own two-backend seam, which under NilPy is never imported at all -- `try: import ctypes / except ImportError: from . import _pxx` takes the _pxx branch, measurably so since 708555fdb, and they only appear as walls because the census compiles every file DIRECTLY. Of the ten that remain: capture.py and gfx.py need ctypes, and CALLING THAT A SEAM EDIT WAS WRONG -- corrected 2026-09-11 (frankB measured, confirmed here): gfx.py uses `ctypes.` SIXTY times across NINE names (byref 21, c_uint 19, c_void_p 5, sizeof 4, c_float 4, c_int 3, create_string_buffer 2, c_char 2, c_char_p 1) plus the `(TYPE * N)(...)` array-type constructor at three sites, and 22 of its 148 `gl.*` call sites marshal through it -- it IS the OpenGL marshalling layer. Routing the import through a try/except makes the module COMPILE and leaves it unable to do the one thing it exists for: the census moves by two and the demo moves by zero. So these two rows are ONE MISSING CAPABILITY (a bounded mimic_ctypes: nine names and an array-type constructor, not all of CPython's ctypes), not two module fixes, and anyone who does the seam edit anyway MUST say in the resolution that ctypes is not solved or two cleared rows will read as the capability landing; threading blocks 3 modules on 2 real sites (__main__ reports gauges.py line 36 through the import chain); sqlite3 blocks 2 subjects on ONE site at world.py:188 (atlas.py:188 is `if box is None:` and has no sqlite3 near it); a module as a VALUE blocks platform/__init__.py with bindings.py cascading behind it; and a field from a qualified module constant blocks traffic.py:402. So the COMPILER owes 8 modules on 4 causes, not 13 on 5. READ THE PER-MODULE LIST, NOT THE COUNT: clearing the *unpack-with-defaults wall moved five modules and only three of them went green -- the other two advanced into a SIGSEGV that was invisible behind it. TWO STANDING RULES FROM THE OWNER, both unusual and both deliberate: (1) WE MAY CHEAT ON THE SOURCE -- where something is principally incompatible with nilpy, changing lekkerzeilen is allowed, which is the opposite of the usual corpus rule; (2) it is NOT to be wired into the test suite, like uforth. It is a target to attempt, not a gate."
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

**3. `ctypes` is not available — and the fork it looked like DOES NOT EXIST.**
This was filed as a Track U decision (emulate `ctypes`, or bind natively and
change the source). **Measurement dissolved it, and the ticket is deleted.**

The project already carries the seam: `lekkerzeilen/platform/__init__.py` selects
a backend and `platform/_pxx.py` is a stub its own author wrote *for this*,
planning `import SDL2/SDL.h` — "the same mechanism behind its wrapper-free
`import sqlite3`". That claim about our compiler is TRUE and tested
(`test_nilpy_import_sqlite.npy` links `libsqlite3.so.0` and calls into it;
`test_nilpy_import_c_header_still_works.npy` guards the route). So arm B is not
"change the source" at all — **filling in a stub the author left for us is
completing the project, not bending it, and the cheat licence is not spent.**

**And native binding already substantially WORKS**, measured against
`compiler/pascal26` a7b03135f504:

| | |
| --- | --- |
| `import "/usr/include/GL/gl.h"` | **compiles and RUNS** |
| `import "/usr/include/SDL2/SDL.h"` | stops on ONE line — `SDL_endian.h:166`, asm constraint `"=Q"` |
| `glGetError()` | compiles and links; dies at exec on `libgl.so` (real name `libGL.so.1`) |

So what looked like "build an FFI subsystem" is **three small, precise
blockers**, now filed and wired above: the `=Q` inline-asm constraint (Track C,
one letter, one site), the header-stem-to-soname mapping, and the inability to
name a header in a subdirectory by anything but an absolute path.

**Decision, and it is settled by measurement rather than taste: bind natively;
do not build `mimic_ctypes` for this target.** Emulating CPython's FFI on top of
a compiler whose designed feature is wrapper-free C interop would be a wrapper
around the mechanism that exists to avoid wrappers. A general `ctypes` shim
remains worth having for arbitrary third-party Python that binds C libraries —
that is a separate feature and this umbrella does not rank it.

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

## RE-MEASURED 2026-09-09 (frankB) — blocker 1 is fixed and blocker 1b took its place

`compiler/pascal26` sha256 `57ba8b0c2c8d`, every `lekkerzeilen/*.py` compiled
one by one. **`undefined variable (__mul__)` is gone from every module.**

The seven modules it blocked are **still blocked, and by one line again**:
`math3d.py:287`, `f = (target - eye).normalized()` inside `Mat4.look_at`. Filed
as [[bug-n-a-user-method-on-a-parenthesised-receiver-of-unknown-type-is-not-parsed]]
and wired above in place of the closed row.

**That residual is NOT new and it was not introduced by the fix.** The PINNED
binary, which predates it entirely, gives the identical error on the identical
line once the alias line is deleted by hand; with the alias line present it
gives the old `54: undefined variable (__mul__)`. Two binaries, one of which has
never seen the change — the control fails differently, which is the point of
running it.

Per-module outcome today (23 files under `lekkerzeilen/`, a wider denominator
than the 16 "runtime modules" the summary counts — not the same number, so do
not read it as a delta against 3):

```
compile clean  5   geometry, scenery, shaders, rd, __init__
parenthesised receiver (blocker 1b)   8   math3d wind rig vessel sim traffic wake __main__
array                                 3   app audio world
ctypes                                2   capture gfx
collections.deque                     1   chart
math.atan2                            1   hud
str.join overload                     1   text
queue                                 1   gauges
```

`wake` and `__main__` are two modules the earlier census did not list under
blocker 1; they fail on 1b through the same import of `math3d`.

## RE-MEASURED again 2026-09-09 (frankB) — blocker 1b closed; 5 -> 7 modules

`compiler/pascal26` sha256 `16efc5348050`. **math3d and wake now compile.** The
seven modules that imported math3d get PAST it and fail on their own next
causes, nearly all already blockers here: `math.atan2` (rig, sim, traffic,
vessel — the deliberate refusal), `array` (app, audio, world), `ctypes`
(capture, gfx), `queue` (gauges), `str.join` (text).

**Two causes are NEW and not yet filed**, both first-error readings that need
reducing before they are worth a ticket:

- `chart:189` — `Nil Python: cannot infer the type of field self.z0`
- `environment`, `__main__`, `wind` at `:141` — `no class declares a method or
  callable ...`

Every number here is a LOWER BOUND: this is a first-error census, so a module
that clears one cause may surface another, which is exactly what math3d did
twice in a row today.

---

## Third census, 2026-09-09 — 7 of 23, and one cause is now the biggest after atan2

Same instrument as the second census: every `lekkerzeilen/*.py` compiled on its
own with `compiler/pascal26`, FIRST error only, so every count here is a LOWER
BOUND — a module with two causes shows one.

**7 of 23 compile clean** (geometry, `__init__`, math3d, rd, scenery, shaders,
wake). Unchanged in COUNT from the second census, and that is the honest
reading: this pass removed a blocker from `chart` without unblocking it, and
`chart` now fails on the cause below instead.

| cause | modules | ticket |
| --- | --- | --- |
| `math.atan2` absent | hud, rig, sim, traffic, vessel (5) | feature-nilpy-math-module-twelve-absent-names-measured |
| closed-world method dispatch | chart, environment, wind, `__main__` (4) | **feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver** — direction settled 2026-09-09, cost is a runtime name lookup |
| `import array` | app, audio, world (3) | feature-n-the-array-module |
| `import ctypes` | capture, gfx (2) | (ctypes) |
| `import queue` | gauges (1) | (queue) |
| `str.join` argument shape | text (1) | bug-n-str-join-rejects-an-argument-shape-cpython-accepts |

### The two causes the second census named, both now reduced and both filed

The second census recorded them as unreduced first-error readings and
deliberately did not file them. Reducing changed what one of them WAS.

**`chart:191` "cannot infer the type of field self.z0"** reduced to four lines
and turned out to have nothing to do with `chart` or with tuple unpacking:
a class field assigned from a bare LOCAL of the same method had no inference
arm at all, where a literal, a parameter, a module global, a global holding an
instance, a global holding a def, and None each had one. **Fixed**
(bug-n-a-field-assigned-from-a-bare-local-has-no-inferable-type). It unmasked
a THIRD gap behind it at `chart:184` — `self.width = self.height = max(...)`,
a chained assignment to two attributes, which does not parse; the module-level
`a = b = 3` does. Filed as
bug-n-a-chained-assignment-to-two-attributes-does-not-parse, and it is
pre-existing at the pin, not a consequence of the fix.

**`environment`/`wind`/`__main__` at `:141` "no class declares a method or
callable field .contains()"** is one defect at one line — `wind.py:141`, which
the other two reach through their imports — and reducing it made it BIGGER, not
smaller: `chart:102` is the same cause (`tile.read_grid("bed")`), so it blocks
four modules, not three. It is the first cause on this umbrella that is a
genuine FORK rather than a gap: NilPy resolves a method call on a dynamically
typed receiver by scanning the classes declared in the compilation unit, and
the closed world is deliberate — it is what catches a typo on a variant
receiver. `canopy`'s class lives in `world.py`, which no module in the package
imports, because that is what duck typing IS. The recommendation and the
measured state of the machinery are on the ticket.

### What did NOT need filing

`math.atan2` stays the single largest cause at five modules and already has its
ticket. Nothing in this pass changes it.

## FOURTH CENSUS, 2026-09-09 (frankB) — the stdlib surface, and what a first-error census cannot tell you

Group taken as one question: **what of the stdlib surface does a real program
actually reach.** Three tickets — `feature-n-the-array-module`,
`bug-n-collections-deque-is-missing`,
`bug-n-str-join-rejects-an-argument-shape-cpython-accepts` — all three fixed and
verified against CPython. **Census total unchanged at 8 of 23.**

### THE FINDING THAT MATTERS MORE THAN THE THREE FIXES

**Every "unblocks N modules" figure on this umbrella counts modules where a gap
is the FIRST wall, not modules the gap is sufficient to clear.** A compiler
stops at the first error, so a blocker census built by reading the first error
of each module can only ever say that. Measured this pass, at compiler
418064fca1d3:

| module | ticket said | wall before | wall after |
| --- | --- | --- | --- |
| `world` | array unblocks it | `no unit named array` | `no unit named struct` |
| `audio` | array unblocks it | `no unit named array` | dispatch (`.queued`) |
| `chart` | deque unblocks it | `collections.deque` | dispatch (`.read_grid`) |
| `text` | join unblocks it | `join` overloads | **compiles** |

Three of four had a second wall behind the first. One did not. Nothing was
wrong with the measurements that produced those numbers — they were honest
first-error readings — but the NUMBER means "first wall here", and it has been
read as "modules this would finish". **Read every count on this umbrella that
way**, including the ones below, and expect the total to move by less than the
sum of the parts.

The cheap correction is to re-measure a module AFTER landing, which is what
produced this table, and to say in the resolution which wall moved rather than
which module was freed.

### The three, landed

- **array** — `lib/rtl/mimic_array.pas`, all twelve typecodes, verified
  byte-for-byte against CPython. No resolver change: the `mimic_` fallback
  already handles it, and a `.pas` shim gets the same free wiring as a `.py` one
  while being able to reinterpret bytes with a pointer cast.
- **deque** — `TPyDeque` in pylib plus one stdlib-table entry. O(1) amortised
  `popleft`, because the caller is a flood fill.
- **join** — the ticket named `str`; the real call is `b"".join(reversed(rows))`
  and the gap was `bytes`. Grepping for siblings found two more, both fixed:
  `bytes(n)` and `sorted()` over bytes.

### What writing them turned up in the COMPILER

Two silent defects, both fixed here, neither reported by anyone:

- **A qualified constructor whose class name is a Pascal reserved word built
  garbage.** `array.array("h")` compiled and evaluated to 104 — `ord('h')` —
  then segfaulted. The reserved-member mapping (`tk.END` -> `END_`) reached the
  value and call paths and not the constructor path.
- **`bytes(n)` refused where `bytearray(n)` was accepted.**

One filed rather than fixed, because it needs new machinery in a hot path:
`bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type` —
two same-arity constructors are not told apart, the first one runs, silently.
The FUNCTION spelling of the same thing is correct, which is the control.

### Blocked-by, re-measured — what actually stands between here and 23

**Counts below are written in the form this census can actually support.**
frankH's point, and it is the right one: a caveat sitting NEXT to a number gets
read as care about the number rather than as a scope on it, so the population
goes INSIDE the phrase or it does not travel. Every figure here is a
**first-wall count, not measured as sufficient**.

| cause | first-wall count; not measured as sufficient |
| --- | --- |
| `math.atan2` (refused, correctly rounded libm) | 6 — hud, rig, sim, traffic, vessel, and one more |
| open-world dispatch on a dynamic receiver | 4 — audio, chart, environment, __main__, wind |
| `ctypes` (settled: bind natively, do not shim) | 2 — capture, gfx |
| `queue` | 2 — gauges, app |
| `struct` | 1 — world |

**The null row is what makes this readable as a measurement rather than a
number** (frankH again): four first walls were cleared this pass and the total
moved by zero. A census with no null row prints a figure where the honest answer
is "unresolved" — so the zero is recorded here deliberately, not apologised for.

`feature-n-the-struct-module` and `feature-n-the-queue-module` are filed with
their measured surfaces. Neither needs a compiler change; both are shims, and
`queue`'s real question is the BLOCKING semantics, not the container — pylib's
new `TPyDeque` is already the right storage for it.

## FIFTH CENSUS, 2026-09-10 (frankuser) — 9 of 28, and the DENOMINATOR moved

Re-measured at HEAD, compiler `61f8a78f8aae`, tree `31dad27bd`, same instrument
as every census before it: every `lekkerzeilen/*.py` compiled alone, first error
only, so every count is a LOWER BOUND.

**9 of 28 compile clean** — figure, geometry, `__init__`, lines, math3d, rd,
shaders, text, wake.

**The denominator is the headline, not the numerator.** Previous censuses said
*of 23*; the tree has 28 runtime modules now. lekkerzeilen is the owner's own
actively developed project — five modules were ADDED since the last census
(`bindings`, `figure`, `lines`, `session`, `ui`) and `scenery.py` was edited
today at 10:50. **So the ratio's denominator moves under the measurement, and a
numerator compared across censuses is comparing two different populations.**
Quote this as "9 of 28 at tree X on date Y", never as a trend against 8 of 23.

Of the original 23, `text` newly passes (its `str.join` ticket closed) and
`scenery` newly FAILS — and that is not a regression on our side: the owner's
`7da065e` added `_sin = math.sin`, filed as
[[bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value]].
Attributed before reporting, because a number moving in the unfavourable
direction invites exactly the self-blaming reading that terminates a search.

| cause | modules | ticket |
| --- | --- | --- |
| `math` surface | hud, rig, sim, traffic, vessel (`atan2`), scenery (`sin` as a value) — **6** | feature-nilpy-math-module-twelve-absent-names-measured + the new value ticket |
| open-world dispatch on a dynamic receiver | audio `.queued`, chart `.read_grid`, environment / `__main__` / wind `.contains` — **5** | feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver |
| `queue` | app, gauges — 2 | feature-n-the-queue-module |
| `ctypes` | capture, gfx — 2 | (bind natively, settled) |
| `struct` | world — 1 | feature-n-the-struct-module |
| `os` data attributes | session — 1 | bug-n-os-environ-and-os-sep-are-not-values |
| `platform.KEY_ESCAPE` | bindings — 1 | NEW, unfiled — qualifier resolves, member does not |
| generator expression as sole argument | ui — 1 | NEW, unfiled — `" ".join(x for x in ...)` at ui.py:576, `expected ')' before 'for'` |

**Two new causes this census, both in modules that did not exist before**, which
is the clearest statement of what attempting a moving target costs: the backlog
does not converge on a fixed 23, it tracks whatever the owner writes next. The
`ui` one is a PARSE error and therefore the cheapest-looking of the lot — a bare
generator expression passed as a function's only argument.

### Delta to the fifth census, 2026-09-10 (frankB) — struct and queue landed, and the total moved by zero AGAIN

Not a sixth census: frankuser's numbers above were re-measured independently
here after `mimic_struct` and `mimic_queue` landed, same instrument, same tree
family, and the clean set is identical — figure, geometry, `__init__`, lines,
math3d, rd, shaders, text, wake. **Still 9 of 28.** Recorded as corroboration
rather than as a new figure, because two agreeing counts from the same method
are one count, not two.

What moved is WHICH wall each blocked module stops at:

| cause | first-wall count; not measured as sufficient | change |
| --- | --- | --- |
| `math.<name>` — atan2, and `sin` in scenery | 7 — hud, rig, scenery, sim, traffic, vessel, **world** | +1 |
| open-world dispatch on a dynamic receiver | 5 — audio, chart, environment, `__main__`, wind | — |
| `ctypes` (settled: bind natively, do not shim) | 2 — capture, gfx | — |
| **`threading`** | 2 — app, gauges | was `queue` |
| `platform.KEY_ESCAPE` through a unit qualifier | 1 — bindings | — |
| `undefined variable (os)` | 1 — session | — |
| `*`-unpacking into a method with defaults | 1 — ui | — |

`struct` and `queue` are gone from the table; `world` moved into the `math`
group and `app`/`gauges` moved to `threading`.

**THE NULL ROW, FOR THE SECOND CONSECUTIVE PASS.** Six first walls have now been
cleared across two passes — array, deque, str.join, sorted-over-bytes, struct,
queue — and the count of modules that compile has moved by **zero** both times.
That is not a disappointing result to be apologised for; it is the measurement
this census exists to produce, and two null rows in a row say something the
first one could not: **clearing a module's first wall essentially never clears
its last.** Every module behind a shim wall had at least one more behind it.

The practical consequence for ranking: **an import-level wall is worth much less
per ticket than its first-wall count suggests**, because imports sit at the top
of a file and are therefore over-represented as first errors. `math` at 7 and
open-world dispatch at 5 are the two that would actually move the numerator, and
neither is a shim.

`feature-n-the-threading-module` (prio 60) is filed with its measured surface —
four names — and with the note that `mimic_queue` must gain a lock and a real
wait in the same change. It is the LAST import-level wall in both `app` and
`gauges`; every other import in both files resolves, measured per-import.

## SIXTH CENSUS, 2026-09-10 — prio 90, and the seam is a STUB

**Owner, 2026-09-10: *"well, this demo app has prio"*, and *"notice that we
don't care compiling tooling right now"*.** Hence `prio: 90`, the top of the
board — above `umbrella-pxx-compiles-fpc-itself` at 85.

**His tooling caveat does not narrow the population, which is itself the
finding.** The import closure from `__main__` reaches **every module in the
package but `__init__`**. The tooling (`tools/import_nl.py` and friends) is
outside it and was never in any census here. So there is nothing to exclude.

**And the previous censuses were measuring too SMALL a population, not too
large:** `lekkerzeilen/platform/` is a SUBPACKAGE, and every census including
mine this morning globbed `*.py` and missed all five of its modules. The app is
**32 modules**, not 23 or 28.

### 8 of 32 at compiler `b7745aaf0a59`, tree `3bebb551e`

Clean: `figure`, `geometry`, `lines`, `math3d`, `rd`, `shaders`, `text`, `wake`.
**All five `platform/` modules fail.**

| cause | modules | note |
| --- | --- | --- |
| `math.atan2` | hud, rig, sim, traffic, vessel, world — **6** | `world` arrived here from `struct` |
| open-world dispatch | audio, chart, environment, `__main__`, wind — **5** | direction settled |
| `ctypes` above/below the seam | capture, gfx, platform/_ctypes_backend, _gl, _sdl2 — **5** | three are the CPython backend and NOT needed under pxx |
| `staticmethod` as a value | platform/`__init__`, platform/_pxx — **2** (+bindings by cascade) | [[bug-n-staticmethod-is-not-a-value]] |
| `threading` | app, gauges — **2** | arrived from `queue` |
| `math.sin` as a value | scenery — 1 | |
| `os` data attributes | session — 1 | |
| `*` unpack at a method call | ui — 1 | arrived from the generator-expression wall |

### The null result, for the third census running

`queue` and `struct` both landed (`1eb448030`) between my morning census and this
one. **The total moved by zero.** `app`/`gauges` went `queue` -> `threading`,
`world` went `struct` -> `atan2`, `ui` went generator-expression -> `*unpack`.
Four walls cleared, four walls behind them. This is the fourth independent
confirmation that a first-wall census cannot predict sufficiency, and it is now
the expected behaviour of this umbrella rather than a surprise.

### THE ACTUAL DISTANCE, WHICH NO RATIO SHOWS

**`platform/_pxx.py` is a 39-line stub whose every entry point raises
`NotImplementedError`.** The app's portability seam has two backends —
`_ctypes_backend` (327 lines, CPython, works) and `_pxx` (not written). So **even
with all 32 modules compiling, the demo would not run.** Filed as
[[task-b-write-the-lekkerzeilen-pxx-platform-backend]], prio 85, and it is the
headline item. Its real blocker is
[[bug-c-inline-asm-constraint-q-is-unsupported-and-it-blocks-every-sdl-header]],
which has sat in `backlog-cfront` while both of its sibling header bugs were
fixed and closed, and is now on the critical path of the top-priority target.

### Edges rewired this pass

Five of the nine `blocked-by` entries were in `done/` — array, deque, str.join,
the GL lowercasing bug, the subdirectory bug — so the umbrella's own ranking had
gone stale in the direction that understates it. Replaced with the live set.

## `ctypes` IS THE GATE — from the consumer, 2026-09-10

neo-dd, asked which of the four broken stdlib imports matters most:

> *"of your real four: **`ctypes` is the one that decides whether lekkerzeilen
> ever runs on PXX at all**, and it is not a library problem. Our entire graphics
> and window layer is SDL2 and OpenGL hand-bound through `ctypes` — that is a
> deliberate constraint, not an accident, and it is why we have no pygame and no
> moderngl to port. `sqlite3` is second: the world tiles are a SQLite database.
> `zlib` and `threading` we could live without in a pinch."*

**So the module-count census is not the ranking.** Of the 14 stdlib modules this
runtime imports, 10 work; of the four that do not, `ctypes` alone decides whether
the program can run, and it is the one that is not shim work.

**And the obligation has been lifted from their side** (their owner, 2026-09-10):
*"it's up to pxx to get on par with cpython ... for now, we focus on zeilen
functionality and should not limit ourselves too much."* They are not building
shims and not shaping the program around our gaps. Read that as removing an
obligation, not withdrawing interest: they stay a truthful corpus and answer
measurements. **So a gap this umbrella finds is OUR ticket, and "lekkerzeilen
could work around it" is no longer an argument for deprioritising one.**

**An offered fixture nobody has taken.** `lekkerzeilen/capture.py` is a
self-contained PNG encoder, ~90 lines of plain Python over `zlib.compress` and
`zlib.crc32`, no third-party imports, deterministic output. Pointed at a fixed
RGBA buffer on both runtimes it exercises `crc32` arity, `compress` arity,
`bytes`/`bytearray` slicing and struct-free big-endian packing in one go, and
fails loudly. neo-dd will produce the fixed input buffer on request. That is a
conformance fixture with its own oracle for the cost of asking.

## ~~THE DEMO WOULD RUN WRONG EVEN WITH EVERY MODULE COMPILING~~ — RETRACTED IN FULL, 2026-09-11

> **RETRACTED BY ITS OWN AUTHOR (frankuser), SAME DAY, AND THE RANKING GOES WITH
> THE WORDING.** There is **no third gate**. lekkerzeilen's four sites use the
> RELATIVE spelling (`from .platform import ...`) and the relative spelling does
> **not** leak. frankZ settled it by building a binary that disables only their own
> hunk (`83b883221d70` = HEAD minus the `SoftUnitMissed` fix, nothing else) and
> running the positive control **in the same run**: the absolute shape leaks to
> None on that binary, proving the bug is present, and the relative shape gives 27
> anyway. So this section's conclusion is false, its four sites were never
> affected, and **the 29-names-across-4-sites count is a true statement about the
> source and a false one about exposure.** Two gates on this umbrella, not three.
>
> **What survives, stated as narrowly as it should be:** a real silent wrong-value
> bug on the **ABSOLUTE** from-import spelling of a module containing a guarded
> import, present in pin `095ef4811a5b` (v407), fixed at `0f0c04b8b`. **Zero known
> live sites in lekkerzeilen.** Worth having fixed — silent, in the pin, ordinary
> construct — and it does **not** gate this umbrella. Do not rank it as if it does.
>
> **All three readings of those four sites were wrong in turn** — mine (silent
> None), frankZ's (hard error instead), and the truth (no effect). Mine failed on
> an untested spelling; theirs failed on a MASKED CONTROL, because the pin cannot
> compile `from .subpackage import NAME` at all, so both arms failed for a reason
> unrelated to the subject and the probe read as a clean discriminating result.
> **A control only controls if both arms can actually exercise the mechanism; two
> failures that agree are not a comparison.** The thing that separated all three
> was building a binary that isolates ONE hunk.
>
> The body below is kept as history because the mechanism it describes is real —
> only its applicability to this umbrella was wrong. Do not act on it.

Measured 2026-09-11 (frankuser), from frankZ's `SoftUnitMissed` finding, with a
control. **This is a silent wrong VALUE, not a compile error**, and it is on this
umbrella's critical path rather than beside it.

The mechanism, reproduced independently before relaying it:

```python
# pkg/__init__.py            # m.npy
VALUE = 27                   # from pkg import VALUE
try:                         # print("v", VALUE)
    from no_such_module import Image
    have = True
except ImportError:
    have = False
```

| | subject (package guards an import) | control (same package, no guard) |
| --- | --- | --- |
| CPython | **v 27** | v 27 |
| pin `095ef4811a5b` (v407) | **v None** | v 27 |
| HEAD `35dce79343cd` | **v None** | v 27 |

The control is what makes it a finding rather than a broken fixture: remove the
guarded import and the identical package gives 27 under both compilers. So the
guard is the trigger. No diagnostic at any point.

**WHY IT LANDS HERE: `lekkerzeilen/platform/__init__.py` IS THE ONLY PACKAGE IN
THE CORPUS THAT GUARDS AN IMPORT** (`try: import ctypes / except ImportError`),
and **four modules from-import names straight out of it**, the entry point among
them:

```
  lekkerzeilen/__main__.py:43  from .platform import KEY_DOWN, KEY_ESCAPE, QUIT, RESIZE, gl
  lekkerzeilen/app.py:26       from .platform import (ARROW_DOWN ... QUIT, RESIZE, gl)   23 names
  lekkerzeilen/gfx.py:10       from .platform import gl
  lekkerzeilen/capture.py:14   from .platform import gl
```

Every one of those names is a plain module-level constant on the other side —
`KEY_ESCAPE = 27`, `QUIT = "quit"`, `KEY_DOWN = "key_down"`, `RESIZE = "resize"`.
Under this defect they all bind to **None**, silently, in the demo's own entry
point.

**So the module count was never going to be the measure, for a second reason
nobody had named.** The umbrella already records that `ctypes` and the unwritten
SDL/GL backend gate whether it RUNS. This is a third gate and it is the nastiest
of the three, because it produces no error at any stage: clear every wall, write
the backend, and `KEY_ESCAPE` still compares against None.

**NOT EXECUTED, and the distinction matters:** those four modules do not compile
yet (the `ctypes` wall), so I have not OBSERVED None in lekkerzeilen. What is
measured is the mechanism, the pin's behaviour, and the presence of the exact
shape at four sites with plain constants on the other side. Treat it as certain in
mechanism and unobserved in situ — and re-check it the moment `platform/` compiles,
because that is the first opportunity to see it directly.

frankZ has the fix at the same choke point (clear the flag before resolving, and
again afterwards when `CompiledUnitCount` went up). **Until a pin carries it, this
is a case where the pin is ACTIVELY WRONG about a construct portable Python
packages write as a matter of course** — a different and stronger argument than
"a fix is inert until pinned". Cross-referenced on
`bug-t-armed-autopin-has-refused-62-consecutive-times-...`.

### RE-MEASURED ON LEKKERZEILEN'S LITERAL GUARD, AND AT origin/master — 2026-09-11, binary `2b72db6e96a1`

The table above used `from <absent> import X` as the guard; lekkerzeilen writes
`import ctypes`, a plain import. **Different statement form, different code path**,
so that was a generalisation step. Removed by measuring all three forms plus the
control, against the pin and against a binary built from `origin/master` tip
`8b188a3be`:

| guard in `pkg/__init__.py` | CPython | pin `095ef4811a5b` | HEAD `2b72db6e96a1` |
| --- | --- | --- | --- |
| `import ctypes` — **lekkerzeilen's literal line** | 27 | **None** | **None** |
| `import <absent module>` | 27 | **None** | **None** |
| `from <absent> import Image` | 27 | **None** | **None** |
| *no guard at all* (control) | 27 | 27 | 27 |

So it is not a family resemblance: **the exact construct in
`lekkerzeilen/platform/__init__.py` returns None**, and the guard is provably the
variable because the control differs in nothing else.

**HEAD IS STILL BROKEN AT origin/master, AND A PEER'S "HEAD IS FIXED" WAS ABOUT A
PRIVATE TREE.** frankZ reported HEAD printing 27 for both forms and asked me to
relax the claim. Their fix is real but **unpushed** — `git log origin/master -S'SoftUnitMissed'
-- compiler/` returns nothing, and the newest compiler commit on origin is
`53c3c3f45` (the dead-arm fix). They measured their own working tree and called it
HEAD, which is the ordinary meaning of the word from inside a session and the wrong
one for anybody else. Had I taken the correction, the owner-facing version would
have said HEAD was clean.

**The rule this is an instance of:** a claim about "HEAD" from a peer is a claim
about THEIR checkout until the sha is on origin. The discriminator is one command
and it is the same one this repo already prescribes for quoting a sha —
`git merge-base --is-ancestor <sha> origin/master`, or for an unlanded change,
`git log origin/master -S'<identifier>'`. Cheap, and it is the difference between
"fixed" and "fixed somewhere you cannot build from".

What does NOT change: the **pin** column, which is the load-bearing half for the
pinning argument, and the four from-import sites. What tightens: the construct is
now lekkerzeilen's own, not a cousin of it.

**And the `not executed` label still stands exactly as written** — the mechanism,
the pin's behaviour on the precise construct, and the four sites with plain
constants opposite are measured; None *arriving in lekkerzeilen* is not, because
`platform/` does not compile yet. frankZ asked for that label to be kept and they
are right to.

### FIXED AT HEAD `0f0c04b8b`, STILL WRONG IN THE PIN — and the population claim re-done with a SECOND FILTER

frankZ pushed the fix (it had been **uncommitted**, not merely unpushed). Re-measured
on lekkerzeilen's literal `import ctypes` guard at origin tip, binary `f1817610c98e`:

| | pin `095ef4811a5b` | HEAD `f1817610c98e` |
| --- | --- | --- |
| `import ctypes` guard | **None** | **27** |
| no guard (control) | 27 | 27 |

**That is the cleanest form this argument can take: the fix exists, it is landed, and
the pin does not have it.** Nothing about the demo's correctness is unknown any more —
only which compiler you build with.

**THE POPULATION CLAIM WAS RIGHT AND MY FILTER WAS WRONG**, which frankZ asked for a
second opinion on precisely because it was load-bearing for ranking and rested on one
grep by one author. `tools/lekkerzeilen_guarded_import_census.py` is the second filter,
built to fail differently — STRUCTURAL (any `ast.Try` whose body contains an
`Import`/`ImportFrom`, whatever the handlers say) where mine was TEXTUAL
(`grep -rln 'except ImportError'`):

```
  lekkerzeilen/platform/__init__.py:91   import ctypes                   handlers: ImportError
  lekkerzeilen/__main__.py:216           from . import app, session, world
                                                   handlers: platform.PlatformError | OSError
  lekkerzeilen/app.py:408                import shutil                   handlers: Exception
```

**Three guarded imports, not one.** My grep missed two, because neither handler
contains the string `ImportError` at all. Had either been a package `__init__.py` I
would have under-reported the population — the conclusion survived by luck, not by
method, and that is the honest way to record it.

**Why the conclusion still holds:** only `platform/__init__.py` is a package
`__init__.py`, and the other two files are **never from-imported** (`grep` for
`from .app import` / `from .__main__ import`: zero sites). No importer exists to
poison. So the four sites stand.

**AND THE CRITERION IS BROADER THAN I STATED, which matters for future code.** A
function-local guard leaks just as well as a module-level one:

| guard placement in `pkg/__init__.py` | pin | HEAD |
| --- | --- | --- |
| module level | None | 27 |
| **inside a function** | **None** | 27 |
| none (control) | 27 | 27 |

So the rule is **any guarded import anywhere in a package's `__init__.py` poisons
every from-import of that package** — not "a module-level guard". Today that is one
file; it is one `try:` in any `__init__.py` away from being more, which is why the
census is a committed tool rather than a number in this ticket.

### THE CRITERION TOOK THREE TRIES — and package-ness was never a dimension

frankZ widened it a third time and was right a third time. Measured, both compilers,
one no-guard control per row:

| module kind | guard placement | CPython | pin `095ef4811a5b` | HEAD `f1817610c98e` |
| --- | --- | --- | --- | --- |
| package `__init__.py` | module level | 27 | **None** | 27 |
| package `__init__.py` | inside a function | 27 | **None** | 27 |
| **plain module** | module level | 27 | **None** | 27 |
| **plain module** | inside a function | 27 | **None** | 27 |
| either | *no guard* (control) | 27 | 27 | 27 |

**So the rule is: any from-imported module containing a guarded import ANYWHERE
poisons every name of that from-import.** Not a package, not module-level. The
package-ness was an artefact of `platform/` being where both of us happened to look.

The three criteria, because the tool is only as good as the criterion and **a
widened filter is exactly when nobody questions it again**:

1. `grep -rln 'except ImportError'` — TEXTUAL. Missed two of three guards here,
   whose handlers are `Exception` and `platform.PlatformError | OSError`.
2. `ast.Try` + "is it a package `__init__.py`" — encoded PACKAGE-NESS, which is not
   a dimension at all.
3. `ast.Try` at any depth in any module, cross-referenced against whether that
   module is actually **from-imported**. The from-import side is what makes a site
   live.

`tools/lekkerzeilen_guarded_import_census.py` implements (3) with controls drawn
from the two things criterion (2) got wrong: its positive control is a PLAIN module
with a FUNCTION-LOCAL guard that is from-imported, so a tool that still filters on
package-ness or placement fails it. Negative control: a guarded module nobody
from-imports must NOT be reported live.

**Result — the conclusion holds, now with an exact count:**

```
  SUSPECTS (contain a guarded import)                      3
  LIVE (from-imported, so actually poisoned)               1  -> module `platform`
      __main__.py:43    5 names   KEY_DOWN, KEY_ESCAPE, QUIT, RESIZE, gl
      app.py:26        22 names   ARROW_DOWN ... QUIT, RESIZE, gl
      capture.py:14     1 name    gl
      gfx.py:10         1 name    gl
                       ---------
                       29 names across 4 sites
  DORMANT (guarded, not from-imported)                     2  -> __main__, app
```

**29 names, not "four sites".** And the two dormant suspects are the forward-looking
risk: `app.py:408` is `import shutil` inside a `try` in a plain module, one
`from .app import ...` away from being live. That is why this is a committed tool
with controls rather than a number in a ticket.

*(Earlier revisions of this section said 23 names at `app.py:26`; the AST counts 22.
Eyeballed from source the first time.)*

## RETRACTED — LEKKERZEILEN'S FOUR SITES WERE NEVER AFFECTED. THE "THIRD GATE" DOES NOT EXIST

Settled 2026-09-11 by building the binary that discriminates. **Everything above
about 29 names reading as None in this demo is WRONG**, and the error is mine: every
leaking cell either of us measured used an **ABSOLUTE** from-import (`from pkg import
X`). Lekkerzeilen's four sites are **RELATIVE** (`from .platform import gl`). Different
spelling, never tested, and I wrote the conclusion as though it had been — the exact
generalisation step I had made frankZ remove from their own table an hour earlier.

frankZ caught it and their first probe could not settle it either: on the **pin**,
lekkerzeilen's shape REFUSES with `undefined variable (KEY_ESCAPE)` — **and so does the
same shape with no guard at all.** The pin cannot compile `from .subpackage import NAME`
for a reason unrelated to guarded imports, so on the pin the guard is not the variable
and neither reading is supported.

**The binary that discriminates is HEAD with frankZ's fix reverted in place** — every
later fix present, this one absent. Built it (`d53760a81f16`, reverse-applied the hunk,
rebuilt, measured, restored, rebuilt, verified the fix back at 27):

| | CPython | `d53760a81f16` = HEAD minus the fix |
| --- | --- | --- |
| **absolute** `from pkg import X`, guarded | 27 | **None** ← the defect, present |
| absolute, no guard *(control)* | 27 | 27 |
| **relative** `from .platform import X`, guarded — **lekkerzeilen's exact shape** | 27 | **27** |
| relative, no guard *(control)* | 27 | 27 |

The absolute row is the **positive control**: it proves this binary HAS the defect, so
the relative row's 27 is a genuine negative and not a masked one. That is the whole
reason the control binary was worth building — without it, "relative gives 27" is
equally explained by a binary that never had the bug.

**So: the defect is specific to the ABSOLUTE from-import spelling, and this demo does
not use it.** No silent None, at any of the four sites, on any binary.

**What survives, precisely:**

- The defect is real and is in pin v407 — for `from pkg import X`. Worth fixing, fixed
  at `0f0c04b8b`, still absent from the pin. That is a general-correctness argument and
  no longer a lekkerzeilen one.
- The **29 names across 4 sites** count stands as a property of the SOURCE. It is not,
  and never was, a count of poisoned names. Read it as "how much crosses that seam".
- A real pin-versus-HEAD gap on this demo remains and is LOUD, not silent: **the pin
  cannot compile `from .subpackage import NAME` at all.** All four sites are that
  spelling, so under `$(PXX_STABLE)` they are a hard error, and something between the
  pin and HEAD fixed it. Loud beats silent, and it is still a reason the pin is behind.
- `ctypes` and the unwritten SDL/GL backend remain the gates on whether the demo RUNS.
  **Two gates, not three.** The third one was my error.

**Why it survived four rounds of widening.** The chain was
`except ImportError` → package-ness → placement → absolute-vs-relative, and each
widening corrected a real error, which is what made the next assumption invisible.
Absolute-vs-relative was never examined because *from-import-ness* felt like the
subject rather than a dimension — the same way package-ness had for me. **The count
was right, the mechanism was right, the population was right, and the SPELLING was
the variable nobody varied.**

## ctypes MUST BE ALL-OR-NOTHING, AND A PARTIAL SHIM IS STRICTLY WORSE THAN NONE

**Measured 2026-09-11 (frankuser), compiler `c53cb51926a2`, and it is a NEGATIVE
result that closes a tempting path.** I wrote a minimal `lib/rtl/mimic_ctypes.py`
— `create_string_buffer` plus the scalar width aliases, differential-clean against
CPython on every row — on the reasoning that the only LIVE ctypes user is
`capture.py`, 49 lines of screenshot code using exactly one name.

**Recorded expectation before the re-run: 27 → 30. Measured: 27 → 25.**

| | |
| --- | ---: |
| regressed (compiled before, fails now) | `bindings.py`, `platform/__init__.py` |
| improved | **none** |

**THE MECHANISM, AND IT IS THE WHOLE FINDING: `import ctypes` SUCCEEDING IS A
SIGNAL THE APPLICATION USES TO CHOOSE ITS BACKEND.** `platform/__init__.py` is

```python
try:
    import ctypes
    from . import _ctypes_backend as _backend    # needs CDLL, POINTER, Structure, ...
except ImportError:
    from . import _pxx as _backend               # the native arm
```

so the moment `ctypes` resolves at all, the seam stops taking the native arm and
commits to the arm that needs the **full FFI**. A partial shim therefore does not
buy partial progress — it **moves the app onto the path it cannot walk**, and it
takes the seam and `bindings.py` down with it. The shim was removed rather than
landed.

**The general shape, which is not about ctypes:** where a corpus uses
`try: import X` as a CAPABILITY PROBE, a partial `mimic_X` is not an increment, it
is a false answer to the probe. Shimming is the right default here (owner,
2026-09-10) and this is the exception with a test attached: **before shimming a
module, grep the corpus for `try: import <that module>` — if the import is a probe,
the shim has to satisfy everything behind the arm it selects.**

### What the ctypes surface actually is, which survives the negative result

22 distinct `ctypes.<name>` uses, 180 sites, five files:

| file | sites | reachable under pxx? |
| --- | ---: | --- |
| `platform/_sdl2.py` | 76 | **no** — backend arm not taken |
| `gfx.py` | 60 | **no** — *nothing in the corpus imports it* |
| `platform/_gl.py` | 27 | **no** — backend arm not taken |
| `platform/_ctypes_backend.py` | 16 | **no** — backend arm not taken |
| `capture.py` | 1 | **yes**, lazily from `app.py:4129` |

14 of the 22 names are scalar width aliases. The machinery is eight: `CDLL`,
`POINTER`, `Structure`, `byref`, `cast`, `sizeof`, `CFUNCTYPE`, and the
`ctypes.util` submodule — **all eight used only by the four unreachable files.**

### The fork, stated in goal terms because it is the owner's

The pieces for a real `CDLL` exist — `lib/rtl/dynlibs.pas` has `LoadLibrary` and
`GetProcedureAddress`, and the ELF writer emits `DT_NEEDED`. What is missing is
what CPython uses libffi for: **calling a pointer with a signature chosen at run
time**, where a Pascal call through a pointer needs a procedure type known at
compile time. So the question is not "implement ctypes" but:

> **Do we want pxx to be able to call any C library a Python program names at run
> time, or only to run this demo natively?**

The first is a bounded-signature call gateway (N integer/pointer/float arguments
and a few return kinds would cover all of SDL and GL) and serves every future
ctypes-using corpus. The second is the ~327-line native `platform/_pxx.py` this
umbrella already names, and touches nothing else. **Both leave the four
unreachable files unreachable, so NEITHER moves the census past what the native
arm needs** — which is the part a reader of the wall histogram would get wrong.

## 2026-09-11, frankZ — 28 of 35 HELD ACROSS THE SEAM REWRITE, which is the row that was open

Independent re-measure at **compiler `465845b20d1e`, tree `3951695c8`, corpus
`63adc17`** — a different compiler and a different corpus revision from the
`f9fb672ee109` / `2a3d60e` run in the summary, so this is a second reading and
not a repeat of that one.

```
28 of 35 modules compile
walls, by modules hitting each FIRST:
   6  import: no unit named ctypes and no shim mimic_ctypes
   1  no member create_string_buffer came of the qualifier ctypes
```

**Expectation recorded BEFORE the run, per this file's own instruction:** 28 of
35, unchanged, ctypes dominant. Matched.

### What was actually at risk, and why the null row is the finding

Corpus `63adc17` is *"platform: restore the try/except/else spelling now that
pxx parses it"* — the seam has been put back on the faithful three-clause form
it wanted all along, so **real application code now depends on
`bug-n-try-except-else-does-not-parse-when-the-try-body-is-an-import`** (fixed
`cc311ec6e`). That fix has two layers, and the second one exists because the
first alone binds the DEAD arm's module through a first-wins alias table,
silently, exit 0. The seam binds `_backend` in both arms, which is exactly that
shape.

So the question this run answered was not "did the count move" but **"does the
faithful spelling select the right backend in real code, or only in my
fixture?"** A regression here would have been mine, not the corpus's, and it
would have shown up as a count BELOW 28. It did not: all seven remaining walls
are ctypes, none is an arm-selection failure, and nothing that compiled before
stopped compiling.

A fixture asserts a construct in the shapes its author chose. This is the same
construct in the shape the application writes, against a backend selection that
matters. Recorded because a null row is only information to someone who said
what they expected — and because "my fixture passes" and "the seam works" are
different claims, which this corpus has already taught once (**a compile is not
a run**, 2026-09-11).

**Goal 4's remaining question is unchanged and is still the owner's**, stated in
the summary: native-library access for NilPy programs, or this app reaching the
native layer through pxx's own binding mechanism with its source changed to
suit. Seven modules, one cause. No compiler ticket is blocking it.

### THE TWO SECTIONS ABOVE AND BELOW AGREE, AND THEY MEASURE DIFFERENT THINGS

Resolved by keeping both (frankuser, 2026-09-11) — they landed as a conflict
only because both were appends. frankZ's run above is an **as-subject census**
and reports 28 of 35 with six modules on `no unit named ctypes` and **one** on
`no member create_string_buffer`. Mine below is the **entry-point closure** and
reports that single `create_string_buffer` row as the only error in the whole
closure. That is the same wall — `capture.py:44` — seen through two instruments,
and the six-module row is the one that does not survive the change of question,
because those six sit in a backend arm the closure never enters.

So frankZ's null row and my one-error closure are the same measurement from two
sides, which is worth more than either alone: the census says nothing regressed
across the seam rewrite, and the closure says what is actually left.

One correction to the section above, and it is to its LAST paragraph rather than
to any of its numbers: *"Goal 4's remaining question is unchanged and is still
the owner's"* — it is not. The closure below shows the demo needs no FFI at all,
and the owner's own `_pxx.py` docstring specifies the native backend as having
*"no create_string_buffer"*. The question is still real for other programs; it
is no longer goal 4's gate. `Seven modules, one cause` is correct as a census
row and is not the demo's distance.

## THE ENTRY-POINT CLOSURE IS **ONE** WALL FROM COMPILING, AND THE FORK IS NARROWER THAN THIS TICKET HAS BEEN STATING — 2026-09-11 (frankuser)

Every census on this umbrella, mine included, has compiled **each module as a
subject** and reported a ratio. The demo does not run modules; it runs
`python3 -m lekkerzeilen`, which is `lekkerzeilen/__main__.py`. Nobody had
compiled that and read the closure.

Measured at `7958322f8`, binary `465845b20d1e`, corpus clean:

```
$ cd /home/neo/lekkerzeilen
$ pascal26 --threadsafe lekkerzeilen/__main__.py /tmp/lzmain
```

**27 lines of output. Seven shim notes, a handful of run-time-dispatch warnings,
and exactly ONE error:**

```
pascal26:44: error: no member create_string_buffer came of the qualifier ctypes
  in: lekkerzeilen/capture.py
```

That is the whole remaining compile distance for the demo. Not seven modules —
one member access, in one function, in one file.

### Why the 28-of-35 number was not telling us this

A module census counts subjects, and this corpus has dead code in it: nothing
imports `gfx.py`, and four of the five `ctypes` files are in a backend arm pxx
never takes. Those rows are real as-subject failures and irrelevant to whether
the demo runs. **The ratio and the closure answer different questions, and only
the closure is goal 4's question.** Keep reporting the ratio if you like — but
the closure is the number to act on.

### The seam's capability probe is CORRECT, which I had left open

`platform/__init__.py` selects its backend with `try: import ctypes / except
ImportError: ... / else: ...`. Probed directly:

```python
try:
    import ctypes  # noqa: F401
except ImportError:
    print("except-arm: no ctypes")
else:
    print("else-arm: ctypes present")
```

pxx prints **`except-arm: no ctypes`**. So the seam picks `_pxx` and the native
arm is genuinely the one under test. The all-or-nothing finding below is about
what happens if a shim makes that probe answer differently; the probe itself is
not broken.

Note the asymmetry, because it is the reason `capture.py` fails the way it does:
the same `import ctypes` **inside a `try`** raises, while at `capture.py`'s top
level, reached as a dependency, it binds nothing and does not raise — so the
error arrives at the member access, not the import. frankB measured the
as-subject half of that on 2026-09-11.

### What is BEHIND that wall — measured, in a scratch copy, not inferred

A first-failure census cannot see past a wall, so the line was stubbed to
`bytearray(...)` in a throwaway copy of the package (the package only: `cp -a`
of the whole tree copies the owner's terrain and filled `/tmp`, which cost a
tier row — see
`bug-a-the-compiler-prints-ok-with-exact-byte-counts-for-an-output-it-failed-to-write`).

The next wall is **one line further down**, `capture.py:45`:

```
error: .ReadPixels() is dispatched at run time (no class here declares it),
and that path takes at most 4 arguments
```

Filed as `feature-n-a-runtime-dispatched-method-call-is-capped-at-four-arguments`.

### BOTH WALLS ARE THE SAME CAUSE, AND IT IS THE STUB

`_pxx.py` defines `class gl:` with **five** staticmethods — `clear_color`,
`clear`, `viewport`, `enable`, `get_string`. It declares neither `PixelStorei`
nor `ReadPixels`, so those calls fall to run-time dispatch, and the 7-argument
one meets the cap. Declare the real surface and **both walls go at once**: the
call resolves statically and `MAX_DYN_ARGS` never applies.

So the compile distance is not "clear ctypes, then clear an arity cap". It is
**write the backend**, which was already this umbrella's second gate
(`task-b-write-the-lekkerzeilen-pxx-platform-backend`). The two walls are that
task reporting itself through the compiler.

### THE DEMO NEEDS NO FFI, AND THE OWNER'S OWN FILE SAYS SO

The fork on this ticket has been stated as *"do we want pxx to be able to call
any C library a Python program names at run time, or only to run this demo
natively?"* The measurement narrows it to a yes/no, because the native answer
needs no ctypes at all. `_pxx.py`'s docstring, written by the owner:

> this backend should be a translation of `_ctypes_backend` in which the
> `ctypes` machinery simply disappears: no CDLL loading, no restype/argtypes
> declarations, **no create_string_buffer**.

`capture.py` names `ctypes` for exactly one thing — a writable byte buffer to
hand `glReadPixels`, read back through `.raw`. That is not FFI; it is a
`bytearray`. Under the native backend the framebuffer read belongs behind the
seam, returning bytes, and `capture.py` should not name `ctypes` at all.

**So the demo is not waiting on a ctypes decision.** It is waiting on the
backend, and the backend's own spec excludes ctypes. The FFI question is a real
question for other programs; it is not this umbrella's.

### What NOT to do with this, and it is the same trap as every census above

`create_string_buffer` is one name and a `bytearray` is sitting right there, so
the cheap move is to shim it. **Don't.** The section below measured what a
partial `mimic_ctypes` does: `import ctypes` starts succeeding, the probe flips,
the seam abandons the native arm for the FFI arm, and the count went DOWN 27 ->
25. Supplying one member makes the probe's answer wrong, not better.

The honest change is on the consumer side — move the framebuffer read behind the
`gl` seam so `capture.py` asks the backend for bytes. That is a two-sided edit
(`_ctypes_backend` keeps the ctypes dance where ctypes belongs, `_pxx` gets the
native one) and it is **pointless until `_pxx.py` exists**, since the whole point
is delegating to a backend that currently raises `NotImplementedError`. Left for
whoever takes that task; not done here, deliberately.

### `blocked-by` WAS SEVEN-TWELFTHS STALE, FOR THE SECOND TIME ON THIS TICKET

Pruned 2026-09-11: seven of the twelve entries were in `done/` — the high-byte
register bug, the dynsym derivation, the dead-guarded-import resolution, the
threading module, open-world dispatch, the stdlib-reference-as-a-value bug,
`*`-unpacking at a method call, and the chained attribute assignment. Five
remain live.

The section at "Five of the nine `blocked-by` entries were in `done/`" above
records the same thing happening earlier on this same ticket, which is why this
is written down rather than quietly fixed. **The edge is the ranker's input and
the body is the history**; a closed blocker left in the list makes an umbrella
read as blocked on work that is finished, and `next` cannot tell the difference.
CLAUDE.md already names this class — the `math.atan2` ticket found closed by
events 26 days earlier — so nothing new is being claimed, only that an umbrella
accumulates it faster than a leaf ticket because it is the only place edges are
written by hand.

One entry was worth keeping apart from the prune:
`feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver` is done,
and it is the feature that BUILT `pydyn_meth0..4`. The four-argument cap filed
today is the ceiling that feature left behind, not a regression in it.
