---
slug: bug-n-a-same-named-rtl-unit-shadows-both-a-relative-import-and-a-mimic-shim
title: "An RTL unit whose name matches defeats a relative import AND a mimic shim — 19 colliding names, one of them lekkerzeilen's seam"
track: N
prio: 85
type: bug
blocked-by: []
status: new
created: 2026-09-10
found: 2026-09-10
found-by: frank-user, from neo-dd's zlib question
owner: ""
summary: "MEASURED 2026-09-10 at 546d4dcbd305. ONE ROOT CAUSE, TWO POPULATIONS: the NilPy unit lookup runs before both relative-module resolution and the mimic_ fallback, so any lib unit sharing a CPython module name wins and then binds NOTHING. 19 lib units collide: ast atexit base64 collections configparser html http io json math pathlib platform random re subprocess tempfile tkinter types zlib. ARM 1, AND IT IS A WALL ON THE TOP-RANKED TARGET: `from . import platform` is an EXPLICITLY RELATIVE import and lib/rtl/platform.pas (the PAL facade) takes it. THAT IS SUFFICIENT TO PRODUCE `pascal26:117: error: no member KEY_ESCAPE came of the qualifier platform` in lekkerzeilen/bindings.py AND I HAVE NOT ESTABLISHED IT IS THE CAUSE FIRING THERE: lekkerzeilen's own platform/__init__.py also fails on its own ([[bug-n-a-module-bound-by-an-import-is-not-a-value]], p90 -- a module is not a first-class value, so `return _pxx, "pxx"` cannot work), so in THAT tree two independent walls can each produce this message and I measured only that this one can. The shadow is proven independently sufficient by a repro containing neither a failing __init__ nor a backend selection; whoever fixes either arm should re-measure bindings.py rather than assume their fix is the one that clears it. Reproduced in four lines with no lekkerzeilen code (pkg/__init__.py, pkg/platform.py defining KEY_ESCAPE, pkg/sub.py doing `from . import platform`), and the POSITIVE CONTROL is the same four lines with the module renamed `seam`: `ok:` and it prints 27. So relative imports WORK and the name shadows. ARM 2, AND I GOT THE DOOR WRONG IN THE FIRST VERSION OF THIS TICKET -- CORRECTED SAME SESSION: `import zlib` does NOT reach lib/rtl/zlib.pas. It reaches the SYSTEM C HEADER /usr/include/zlib.h. Proof by which names bind: `zlib.uncompress`, `zlib.zlibVersion`, `zlib.deflateInit_` and `zlib.crc32` all resolve (C API), while `zlib.InflateZlib` -- Pascal-only -- answers `no member`. So there are THREE doors ahead of the shim, not one: a system C header, then a Pascal unit, then a sibling/relative .py, and mimic_ last (pasparser_proc.inc:6500, `consulted only after every ordinary lookup has failed'). The C-header door is the worst of the three because it binds a LOT and all of it is wrong for a Python caller: C `compress` takes four arguments to CPython's one, which is why `zlib.compress(b"x")` answers `no overload matches` rather than anything about a missing module. AND THE BINDING IS DEAD ON ARRIVAL: the compiler derives the soname from the HEADER name, giving `libzlib.so`, which no machine answers to -- its own diagnostic says `a header file name is not a library name`. Which collisions take which door is decided by whether a header exists: zlib.h and math.h are present, json.h/io.h/types.h are not, and platform.h is not -- so `platform` takes the PASCAL door, measured (`platform.PAL_STDOUT` binds). So a mimic_zlib COULD NOT BE REACHED IF SOMEONE WROTE ONE, which matters because the owner's standing instruction (2026-09-10) is to craft a shim for a missing lekkerzeilen library feature. TWO DIFFERENT FIXES, do not conflate them. Arm 1 is unambiguous and narrow: a relative import (pyRelLevel > 0) must never consult the global unit namespace at all -- the program said `.`, and no RTL unit can satisfy that. Arm 2 is a precedence call AND THE OWNER HAS RULED ON IT, 2026-09-10: `and importing preference whitelist we can just hardcode. 'zlib? -> rtl zlib unless...'` -- so the shape is an explicit per-module preference table in the compiler, not an inferred rule, and a table is the right answer precisely because the three doors are not rankable in general (math SHOULD take its shim, platform SHOULD take the relative module, and neither follows from a single global order). The machinery to key it on is already present: PyImportLang records that a `uses` was written as Python (pyparser.inc:38273, added for exactly this kind of keying). The quoted form `import 'zlib.pas' as z` stays as the explicit door to the unit -- it WORKS today and is how this was measured. AND THE PASCAL DOOR IS ITSELF HALF-OPEN: through the quoted import InflateZlib binds, then refuses every argument shape NilPy can build (bytes, bytearray, list-of-int, return-lifted) because it wants hashing.pas's `TByteArray = array of Byte`, so a Python caller cannot reach the unit even when the name resolves. That is why the shim must be PASCAL-side, as mimic_struct.pas already argues for itself."
---

# One shadow, two populations

## The census

19 units under `lib/rtl` and `lib/pcl` carry a CPython stdlib module name:

```
ast  atexit  base64  collections  configparser  html  http  io  json  math
pathlib  platform  random  re  subprocess  tempfile  tkinter  types  zlib
```

Some of those are deliberate and good — `math` is auto-used by NilPy, and the
resolver comment names `lib/rtl/re.pas` as a unit that is *supposed* to win.
This ticket is not "rename them". It is that **winning and then binding nothing
is not winning**, and that two separate resolution steps are being pre-empted.

## Arm 1 — a relative import is defeated, and it is lekkerzeilen's seam

`lekkerzeilen/bindings.py:43` is `from . import platform`, and `lib/rtl/platform.pas`
is the PAL facade. The reported wall is `bindings.py:117`:

```
error: no member KEY_ESCAPE came of the qualifier platform
```

Reproduced with no lekkerzeilen code at all:

```
pkg/__init__.py      (empty)
pkg/platform.py      KEY_ESCAPE = 27
pkg/sub.py           from . import platform
                     print("KEY_ESCAPE =", platform.KEY_ESCAPE)
```

→ `pascal26:2: error: no member KEY_ESCAPE came of the qualifier platform`

**Positive control — the same four lines, module renamed `seam`:**

```
pkg/seam.py          KEY_ESCAPE = 27
pkg/sub2.py          from . import seam
                     print("KEY_ESCAPE =", seam.KEY_ESCAPE)
```

→ `ok: sub2` … `KEY_ESCAPE = 27`

So relative imports are not broken. The name is shadowed. The control is drawn
from the population the question is about — same construct, same package, one
character of difference that is the hypothesis — and it is the asymmetry that
makes it a control rather than a second subject.

**The fix for this arm has no design fork in it.** `from . import X` names a
module relative to this package. No unit in `lib/rtl` can be that module, ever,
under any precedence policy. So for `pyRelLevel > 0` the unit lookup must not
run at all. That is the whole of arm 1, and it unblocks `platform/` — which the
lekkerzeilen census has as the gate on `bindings`, `app`, `gfx`, `capture`,
`__main__` and the seam's own `__init__`.

## Arm 2 — a mimic shim is unreachable under a colliding name

`import zlib` compiles (`ok:`, and the unit is linked in — 1.28 MB binary), and
then nothing is bound:

```
zlib.decompress(...)    → no member decompress came of the qualifier zlib
zlib.InflateZlib(...)   → no member InflateZlib came of the qualifier zlib
from zlib import InflateZlib → undefined variable (InflateZlib)
```

`pasparser_proc.inc:6500` states the order in its own comment:

> The mapping is consulted only after every ordinary lookup has failed, so a
> real unit of that name (lib/rtl/re.pas, a sibling .py) always wins and Pascal
> `uses` is untouched.

Correct as designed, and it means **a `mimic_zlib` written tomorrow would never
be consulted.** No shim currently collides (measured: the 21 existing
`mimic_*` names and the 19 colliding unit names are disjoint), so nothing is
broken today — this is a trap that springs the first time someone shims a
module we already have a unit for, which is precisely what the owner's
instruction to craft shims makes likely.

**The recommended precedence, with the machinery already in place.** The
frontend already records *why* a `uses` exists: `PyImportLang`, added at
`pyparser.inc:38273`, whose comment says it exists so the rule is *"keyed on
something the parser KNOWS instead of on a predicate that merely correlates
with it."* A NilPy **import statement** asked in Python and should get Python
semantics, so it should prefer `mimic_<name>` over a same-named Pascal unit;
a Pascal `uses` is untouched, because it is not an import statement. The door
to the unit stays open and is the one this ticket measured through:

```python
import 'zlib.pas' as z     # works today — binds InflateZlib
```

This half is a precedence change with a visible blast radius (the 19 names),
so measure it per name rather than asserting it: for each, does any `.py` in
the tree or the corpora import it expecting the unit?

## And the Pascal door is half-open anyway

Through the quoted import, `InflateZlib` **binds** — and then refuses every
argument shape NilPy can construct:

| call | result |
| --- | --- |
| `z.InflateZlib(src, dst, err)` with `src = bytes([...])` | no overload matches |
| `z.InflateZlib(bytearray(src), dst, err)` | no overload matches |
| `z.InflateZlib(list(src), dst, err)` | no overload matches |
| `ok, dst, err = z.InflateZlib(src)` (return-lifted) | no overload matches |

It wants `hashing.pas`'s `TByteArray = array of Byte` — a Pascal dynamic array,
and NilPy has no spelling that builds one. (Note for whoever touches this:
`sysutils.pas` declares a **different** `TByteArray = array[0..32767] of Byte`
and says so in its own comment — two types, one name.)

So even with the name resolved, a Python-side caller cannot reach the unit.
**This is the argument for the shim being Pascal-side**, which is exactly what
`mimic_struct.pas` says about itself: the resolver does not care whether it
finds `mimic_X.pas` or `mimic_X.py`, and the one to pick is whichever language
can do the job. Here, only Pascal can hold a `TByteArray`.

## Follow-on, not part of this ticket

A `mimic_zlib.pas` exposing CPython's `decompress(data) -> bytes` over
`InflateZlib` is the thing neo-dd actually wants, and it is blocked on arm 2.
Filed separately so this one stays a compiler bug:
[[feature-n-mimic-zlib-gives-nilpy-cpythons-decompress-over-the-rtl-inflater]].
Note for that work: `lib/rtl/zlib.pas` only DEFLATES as stored blocks
(`DeflateZlibStored` — valid zlib, no compression), so `compress` can be honest
about round-tripping and must not claim a ratio.

## `math` is the counter-example, and the whitelist must not break it

Measured 2026-09-10, because neo-dd predicted from the export lists that `math`
would be the worst case — 21 of ~30 lekkerzeilen modules import it, and a
case-insensitive Pascal bridge would make nine of seventeen names silently work
while `atan2`→`ArcTan2`, `log`→`Ln` and `radians`→`DegToRad` failed scattered
across twenty-one files. **That prediction is wrong, and it is worth recording
why, because the reasoning was sound.**

`math` does not go through a naive name bridge. It has a deliberate
compiler-provided shim layer, and the layer says so in its own diagnostic:

> `math.atan2` is a compiler-provided shim and can only be CALLED, not taken as
> a value — the call site adds the domain, overflow and arity handling that make
> it match CPython

All seventeen names neo-dd listed are reachable, under their **CPython**
spellings, including the six they expected to need renaming. Ten called and
diffed against CPython: eight byte-identical, and `tan` and `exp` differ in the
last digit only (1 ULP on a transcendental — Track F by definition, and the
goal file's rule is the value stored in its declared type, not the intermediate).

`math.pi` is a float and not a function, despite `math.pas` exporting `Pi` as a
function.

**Two consequences for the fix.** First, a preference table must leave `math`
alone — it is already routed correctly and is the model for what the others
should look like. Second, **my own first probe of these names manufactured a
failure**: I took them as values (`x = math.atan2`), which is the one spelling
the shim refuses, and read five "absent" names off it. A caller writes a call.
Probe the construct the consumer actually writes.

## The population this fix serves, measured

lekkerzeilen's whole runtime import surface is 14 stdlib modules and no
third-party anything (neo-dd, 2026-09-10). Each probed with a characteristic
CPython call at 546d4dcbd305:

| module | state | door |
| --- | --- | --- |
| `collections` `json` `math` `os` `sys` `time` | **works** | native / compiler shim |
| `array` `queue` `struct` `urllib` | **works** | `mimic_array` `mimic_queue` `mimic_struct` `mimic_urllib_parse` |
| `zlib` | broken — **collision** | system C header (`zlib.h`) |
| `sqlite3` | broken — **collision** | system C header (`sqlite3.h`) |
| `threading` | broken — **absent** | no header, no unit, no shim |
| `ctypes` | broken — **absent** | ditto, and a different animal |

So **10 of 14 work**, and of the four that do not, **two are this ticket and two
are not.** `threading` already has [[feature-n-the-threading-module]] at p90.
Do not let this ticket be read as gating all four.

`platform` — the seam — is a fifth collision and takes the **Pascal** door, not
the C one, because no `platform.h` exists.

### Why the C-header door survived: it is right by accident for `sqlite3`

The soname is derived from the header's stem, and that is wrong in general:

| header | derived | real | outcome |
| --- | --- | --- | --- |
| `zlib.h` | `libzlib.so` | `libz.so` | dead at exec |
| `sqlite3.h` | `libsqlite3.so` | `libsqlite3.so` | **loads** |

One rule, one module where the stem happens to be the library name and one
where it is not. `sqlite3.sqlite3_open` and `sqlite3.sqlite3_libversion` bind
and would run; `zlib.crc32` binds and would not. That is very likely why the
derivation is still in the tree — **the case anyone tried first worked.** The
soname half belongs to frankH's existing derived-soname ticket (the SDL2
blocker) and has been relayed there with this as the smaller repro; it is not
part of this ticket, and fixing it does NOT give a Python caller CPython
semantics — C `compress` still takes four arguments to CPython's one.

## THE RULE, FROM THE OWNER, 2026-09-10 — and Pascal already obeys it

> *"our import rules are like. native language first. built-in and rtl libraries
> first. so zlib.pas has prio over /usr/include/zlib.h in case we specify 'zlib'
> in pascal or python.."*

**So this is a straightforward bug against a stated rule, and it is narrower
than the rest of this ticket says.** Measured at 546d4dcbd305:

| spelling | resolves to | verdict |
| --- | --- | --- |
| Pascal `uses hashing, zlib` | `lib/rtl/zlib.pas` — `InflateZlib` runs, answers `zlib stream too short` on empty input | **correct** |
| NilPy `import zlib` | `/usr/include/zlib.h` — `zlibVersion` binds from `libzlib.so` | **violates the rule** |

The Pascal path is already right. **Only the NilPy import path puts a system C
header ahead of our own unit**, so the fix is in that path and the blast radius
is NilPy imports, not `uses`.

### THE RULE IS A MEANS; PREDICTABILITY IS THE END (owner, same evening)

> *"well, my ruling is not absolute. it's because mixing languages creates a big
> mess where no-one can predict the outcome."*

**Record this above the ordering, because it is the test that survives when the
ordering is argued about.** The question to ask of any resolution change is not
"is this the right precedence" but **"can a reader of the import site predict
what it binds?"** An ordering is one way to buy that; it is not the goal, and
the owner has said in his own words that it is not absolute.

Measured, and it is worse than the language mixing he described — **the outcome
depends on the MACHINE, not only on the languages present:**

| | |
| --- | --- |
| `import zlib`, native | binds `/usr/include/zlib.h` |
| `import zlib`, `--target=i386` | binds `/usr/include/zlib.h` |
| `import zlib`, `--target=wasm32` | **binds `/usr/include/zlib.h`** |
| `import zlib` on a box with no `zlib.h` | would fall through to `lib/rtl/zlib.pas` |

So a **wasm32** build resolves a Python import against this Linux host's C
headers and derives `libzlib.so` for a target that has no shared libraries at
all. (riscv32 and xtensa could not be measured — they refuse earlier, on `a heap
arena needs mmap`, which is upstream of resolution.)

Nothing at the import site distinguishes any of these rows. The same four
characters bind a Pascal unit, a C header or a Python shim depending on what is
installed on the box doing the compiling — which makes the source's meaning a
property of the build host. That is the unpredictability to fix, and an ordering
that consults the host's `/usr/include` for a cross target is not fixed merely
by being reordered: **a bare Python import should not reach the host's C headers
at all**, on any target.

The cross rows are also the cheapest positive control for whoever takes this: a
wasm32 build binding a host glibc header cannot be correct under any precedence
policy, so a fix that still does it has not worked.

### What "ours first" means for a PYTHON import

`lib/rtl/mimic_*` are RTL files — the RTL's own Python face, not a third-party
fork — so a mimic IS "built-in and rtl". For `import zlib` the order that
satisfies the rule and also produces something callable is:

1. `mimic_zlib` — ours, CPython-shaped
2. `lib/rtl/zlib.pas` — ours, Pascal-shaped (and in practice unreachable from
   NilPy: it wants `hashing`'s `TByteArray` and NilPy has no spelling for one)
3. **never** the system header for a bare name

Rung 2 being effectively dead from Python is not an argument against the order —
it is why the mimic has to exist. The explicit door to the unit stays
`import 'zlib.pas' as z`, which works today.

### The one case the rule does not cover, decided rather than escalated

`from . import platform` carries a leading `.`, which is the program scoping the
name to ITSELF. "Built-in and rtl first" is a rule for resolving a **bare**
name; a dotted-relative import is not one. So the program's own module wins
there, independent of this ordering — otherwise lekkerzeilen's seam stays broken
by a rule written about something else. Recorded as decided, not asked, because
it follows from what the spelling means; relayed to the owner for contradiction
in the same breath. **If he reads it the other way, arm 1 of this ticket becomes
a Track U question and lekkerzeilen's `platform/` package needs renaming
instead** — which is the consequence to weigh, and it is a rename in a consuming
program rather than a compiler change.

## ARM 1'S MECHANISM IS WRONG AND ITS POPULATION IS TWO, NOT NINETEEN — frankZ, 2026-09-11, compiler `fe40bf55e141`

Not a criticism of the ticket, which is the reason any of this was findable. But
whoever takes arm 1 should not start from its stated cause, because I did and it
cost a rebuild-and-measure cycle to find out.

**THE DOT IS IRRELEVANT.** Arm 1 says *"a relative import (pyRelLevel > 0) must
never consult the global unit namespace at all — the program said `.`"*. That is
a true statement about intent and it is not this bug. A **bare** sibling import
fails identically:

```
dir/platform.py + dir/main.py:  import platform          -> no member MARKER
dir/pathlib.py  + dir/main.py:  import pathlib           -> sibling wins, 27
```

Same directory, same shape, no package and no dots. **I implemented arm 1 as
written** — closed the Pascal chain and the host-header chain for
`pyRelLevel > 0` — rebuilt, and it measured as **NO CHANGE on every name I
could construct**, before and after, with the fix stashed and restored. Dropped
rather than landed: a narrowing no probe can distinguish is speculative code.

**THE POPULATION IS TWO.** The nineteen is a count of NAME collisions, not of
the symptom. Measured, all nineteen, each with a sibling `<name>.py` defining
`MARKER = 27`:

| result | names |
| --- | --- |
| **sibling wins, correct** | ast atexit base64 collections configparser html http io json math pathlib re subprocess tempfile tkinter types zlib — **17** |
| **shadowed** | **platform**, **random** — 2 |

And the two fail **differently**, so they are probably not one mechanism:

```
platform   no member MARKER came of the qualifier platform
random     undefined variable (random)
```

`PyRtlUnitServesPython` does not explain it either, which is the tell that sent
me looking elsewhere: `platform` is NOT in that list and `random` IS, and both
misbehave; `pathlib` is in it and `zlib` is not, and both are fine.

## WHAT THE EVIDENCE POINTS AT INSTEAD — a hypothesis, stated as one

**The door is the already-compiled guard, not the chain.** `ParseUsesUnit`
scans `CompiledUnitKey` for the name and takes an early exit before any `.pas` /
`.py` / header probe runs. Nothing in the chain can be reordered to beat it.

What makes `platform` different from the seventeen: **the RTL pulls it in
itself.** `grep` for units naming it in a `uses` clause —

```
platform  25      base64/http/json/math/random/zlib  2-3      the other 13  0
```

`lib/rtl/platform.pas` is the PAL facade and `baseunix.pas` and `classes.pas`
are among the 25, so it is compiled in essentially every program before the
program's own import is parsed. `platform.PAL_STDOUT` binds and prints `1`,
which says the import reached the Pascal unit; `pathlib.PAL_STDOUT` does not.

**Not established:** that the guard is where it is decided, and nothing about
`random`, whose message says the name did not bind as a qualifier at all rather
than binding to the wrong thing. Both want the same next step and it is one
step: print what `ParseUsesUnit` resolves for these two names, rather than
inferring it from which members bind.

## THE COROLLARY THAT MATTERS FOR RANKING

If the door is "already compiled", then **the fix cannot be a precedence table**
in the general case — the owner's ruling (a hardcoded per-module preference
table) is about arm 2 and stays right for arm 2, but a table consulted in the
chain never runs for an ambient unit. Whatever lands has to act at or before the
guard.

## THE CORPUS SHAPE, ISOLATED, WITH ITS OWN CONTROL IN THE SAME RUN

lekkerzeilen's `platform/` is a package DIRECTORY, not a flat module, and that
was worth checking separately rather than assuming:

```python
# pkg/__init__.py
from . import platform          # pkg/platform/__init__.py: KEY_ESCAPE = 27
from . import seam              # pkg/seam/__init__.py:     KEY_ESCAPE = 27
print("pkgdir", platform.KEY_ESCAPE, seam.KEY_ESCAPE)
```

CPython: `pkgdir 27 27`. pxx: `no member KEY_ESCAPE came of the qualifier
platform`, with `seam` — the identical package one line down — fine. **The
control is inside the run**, so it cannot pass by having been dragged in by
something the failing half needed.
