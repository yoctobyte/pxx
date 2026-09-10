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
