---
slug: bug-n-a-from-imported-class-loses-its-methods-unless-it-is-renamed
track: N
prio: 80
type: bug
blocked-by: []
status: backlog
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "`from .platform import gl` then `gl.get_string()` raises AttributeError at run time, while `from .platform import gl as zz` then `zz.get_string()` works -- same class, same program. Constants read correctly on BOTH, so the binding looks fine. The trigger is the local name being EQUAL to the member's name; `as <different name>` is the whole difference. Compiles clean; found only by running. Blocks 117 gl method calls across lekkerzeilen's gfx.py (110), __main__.py (6) and capture.py (1) -- i.e. the entire renderer."
---

# A from-imported class loses its methods unless it is renamed

Two programs, identical but for one word:

```python
from .platform import _pxx
from .platform import gl                 # or `as gl` -- same thing
win = _pxx.open_window("n1", 320, 240)
print(gl.COLOR_BUFFER_BIT)               # 16384          <- correct
print(gl.get_string(0x1F02))             # AttributeError: 'type' object has no
                                         #   attribute 'get_string'
```

```python
from .platform import gl as zz           # the ONLY change
print(zz.COLOR_BUFFER_BIT)               # 16384
print(zz.get_string(0x1F02))             # 4.5 (Core Profile) Mesa 26.0.8
```

`class gl` is a NilPy class used as a namespace, members `@staticmethod`.
Measured 2026-09-11 at `120eeb39f` plus the `not`-on-pointer fix, binary
`c7099023af6a`, under `xvfb-run`.

| local name | member | constant | method |
| --- | --- | --- | --- |
| `gl` (bare) | `gl` | 16384 | **AttributeError** |
| `gl` (`as gl`) | `gl` | 16384 | **AttributeError** |
| `zz` (`as zz`) | `gl` | 16384 | works |
| `gls` (`as gls`) | `gl` | 16384 | works |

## What I got wrong first, because it matters for whoever picks this up

I filed this as *"...when the subpackage is also bound"*, on a matrix where the
failing case also had `from . import platform` and the working case did not. That
was a **confound**: the real discriminator is the local name, and
`from . import platform` is irrelevant — a bare import with no subpackage
binding fails too, and an aliased one with the subpackage bound works. Three of
the four rows above were in the original matrix; the fourth is the one that
separates the two hypotheses, and it took one extra program to get.

The general shape is CLAUDE.md's: two observations differing in two ways at
once, and the obvious difference is not the operative one.

## Why it survived

**The constant reads correctly on both sides.** So a reader checking "did the
import bind?" gets yes, with a true GL value, and the failure arrives later at
the first method call. Compilation is clean and silent — the closure compiles
through `gfx.py`'s 110 `gl.` calls without a warning.

That is also why "it compiles" was mistaken for progress here: `gfx.py`
compiling says nothing about `gfx.py` running.

## Population

| file | `gl.` method calls |
| --- | --- |
| `lekkerzeilen/gfx.py` | 110 |
| `lekkerzeilen/__main__.py` | 6 |
| `lekkerzeilen/capture.py` | 1 |

All three import it bare. `__main__.py:159` (`gl.get_string(gl.RENDERER)`) is in
`--m0`, the smallest runnable mode, so this is the first thing the demo hits.

**The corpus workaround is one word and that is an argument for fixing the
compiler, not the corpus**: `as _gl` at three import sites would paper over a
defect whose whole danger is being invisible.

## Where to look

The from-import binding path in `pyparser.inc` — `PyParseOneImport` /
`PyBindImportUnitAlias` — for the case where the bound local name is spelled the
same as the member being imported. The working `as` form takes a path that ends
in a statically-known class; the same-name form appears to end in a run-time
value (the error says `'type' object`, so something class-shaped arrives, just
not one whose staticmethods resolve). A plausible mechanism is the same-name case
short-cutting to a unit-alias registration — `from . import X` and
`from .pkg import X` share that helper — and a unit alias having no route to a
class member.

**Not established:** whether this affects from-imported *functions* and
*variables* as well as classes, whether an absolute spelling behaves the same,
and whether it is specific to `@staticmethod` versus instance methods. One
program each.


## 2026-09-13 (frankZ) — NO VERDICT: PROBE PROVEN VACUOUS AGAINST A KNOWN-BAD CONTROL

**Not "could not reproduce".** The probes were run against a compiler KNOWN to
hold the defect and passed there too, which measures the instrument and not the
bug.

Attempted as part of the "class held as a value" group. **I could not reproduce
this at HEAD — and I could not reproduce it on pin v408 either**, which is the
part that matters: v408 PREDATES `575e9ec16` and `5445b96d8`, the two commits
that claim exactly these shapes. A probe that does not fail on a compiler where
the bug demonstrably existed has not reached the defect, so my passing result
says nothing about whether it is fixed. Recording that rather than a green.

Shapes tried, all correct on BOTH v408 and HEAD, all matching CPython:
`g = gl; g.s()` with a lone `@staticmethod` carrier; the same with the name also
an instance method on two other classes (the multi-carrier condition `5445b96d8`
names); a dict value `d["k"].s()`; a function parameter `viaparam(gl)`; the same
through a module attribute `g = m_backend.gl`; and a full PACKAGE with relative
imports mirroring lekkerzeilen's seam — `platform/__init__.py` doing
`gl = _backend.gl` over a `class gl:` of staticmethods, consumed by a sibling
module's `from .platform import gl`.

**What this is an instance of:** a guard that cannot fail. The route my probes
took was not the route under test, and the positive control (does it fail on the
known-bad compiler?) is what exposed that — see CLAUDE.md, "isolation guards the
RUN, not the ROUTE", and the playbook section of the same name.

**So this ticket needs either the original reporter's repro or a run against the
lekkerzeilen corpus it cites, not another minimal probe from me.** The likely
closers are `575e9ec16` (PyParseVariantMethod's hoisted `pyvar_is_objtag` guard
refusing a VT_CLASSREF receiver) and `5445b96d8` (PyClassLevelOnlyMeth refusing
a class receiver for any name with an instance carrier), both verified by their
authors against lekkerzeilen. Someone with that corpus should close it; I am not
closing it on a vacuous probe.

**The group hypothesis is DEAD FOR NOW — not "untested", which a later reader
will mis-read as "promising" and spend an evening on.** It was never in a
position to be true or false, because two of its three inputs never fired: you
cannot read two triggers against each other when only one of them reproduces.
It becomes live again only if arms 1 and 3 get a repro that actually fails on a
known-bad compiler. Recorded, with its reason for being unresolved, so nobody
re-derives it:
frankuser proposed reading this arm's trigger against
`bug-n-an-attribute-read-through-a-class-bound-to-a-variable-gives-a-raw-address`
— same-name breaks method lookup, different-name breaks the attribute read, one
resolver keyed on the name. I could not test it, because I could not reproduce
two of the three arms. It stays a hypothesis.
