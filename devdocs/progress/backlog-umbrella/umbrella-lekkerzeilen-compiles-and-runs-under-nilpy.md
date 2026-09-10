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
  - feature-n-derive-a-header-s-library-from-its-directory-and-verify-it-against-the-library-s-own-dynsym
  - bug-a-the-x86-64-encoder-cannot-name-a-high-byte-register
  - bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved
  - feature-nilpy-math-module-twelve-absent-names-measured
  - feature-n-open-world-method-dispatch-on-a-dynamically-typed-receiver
  - feature-n-the-threading-module
  - bug-n-os-environ-and-os-sep-are-not-values
  - bug-n-a-stdlib-function-referenced-without-calling-it-is-not-a-value
  - bug-n-star-unpacking-is-rejected-at-a-method-call
  - bug-n-a-chained-assignment-to-two-attributes-does-not-parse
  - bug-n-a-module-bound-by-an-import-is-not-a-value
summary: "Owner-set target (2026-09-08): the lekkerzeilen sailing simulator -- /home/neo/lekkerzeilen -- as a REAL-WORLD nilpy target. It was written knowing about pxx and it shows: the runtime package imports ZERO third-party libraries (numpy and PIL appear only under tests/ and tools/), there is not one f-string in it, and no async, yield, match, walrus or annotation. RE-MEASURED 2026-09-10 at compiler a812b9549413, tree 813c99cc7: 22 of 35 modules compile clean. THE CORPUS MOVES UNDER YOU -- the owner renamed flight.py to drone.py at 15:47 and added atlas.py at 16:30 the same day, so it was 34 modules that morning and a delta between two censuses is not attributable to compiler work unless you check. The 13 remaining walls are FIVE causes, and THREE OF THE THIRTEEN ARE BY DESIGN AND OWE THE COMPILER NOTHING: platform/{_ctypes_backend,_gl,_sdl2} are the CPython arm of the app's own two-backend seam, which under NilPy is never imported at all -- `try: import ctypes / except ImportError: from . import _pxx` takes the _pxx branch, measurably so since 708555fdb, and they only appear as walls because the census compiles every file DIRECTLY. Of the ten that remain: capture.py and gfx.py import ctypes at module level with no seam, which is a CORPUS change (the owner's standing rule allows it) and Track B's task-b-write-the-lekkerzeilen-pxx-platform-backend, not compiler work; threading blocks 3 modules on 2 real sites (__main__ reports gauges.py line 36 through the import chain); sqlite3 blocks 2 subjects on ONE site at world.py:188 (atlas.py:188 is `if box is None:` and has no sqlite3 near it); a module as a VALUE blocks platform/__init__.py with bindings.py cascading behind it; and a field from a qualified module constant blocks traffic.py:402. So the COMPILER owes 8 modules on 4 causes, not 13 on 5. READ THE PER-MODULE LIST, NOT THE COUNT: clearing the *unpack-with-defaults wall moved five modules and only three of them went green -- the other two advanced into a SIGSEGV that was invisible behind it. TWO STANDING RULES FROM THE OWNER, both unusual and both deliberate: (1) WE MAY CHEAT ON THE SOURCE -- where something is principally incompatible with nilpy, changing lekkerzeilen is allowed, which is the opposite of the usual corpus rule; (2) it is NOT to be wired into the test suite, like uforth. It is a target to attempt, not a gate."
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
