---
slug: bug-n-a-from-imported-class-loses-its-methods-unless-it-is-renamed
track: N
prio: 80
type: bug
blocked-by: []
status: done
found: 2026-09-11
found-by: frankuser
owner: unassigned
summary: "FIXED IN THE CORPUS, 2026-09-13 -- and the REPAIR IS NOT ATTRIBUTED, which is the part a later reader must not lose. The exact repro of this ticket now works in the very tree that reported it: lekkerzeilen `platform/__init__.py` binds `gl = _backend.gl` over `class gl:` in `_pxx.py` (91 @staticmethods, `get_string` among them), four modules do the same-name `from .platform import gl` with no rename -- gfx.py:10, capture.py:13, __main__.py:46 and app.py:26, two of them in a multi-name list -- and the pxx-BUILT binary prints `gl : 3.3.0 NVIDIA 580.178.04` from `gl.get_string(gl.VERSION)` at __main__.py:160, with the render loop reaching a GL 3.3 context and a loaded world. NO COMMIT IS CREDITED: frankh-30, who ran it, did not touch the guarded-import machinery (their two commits today were PyWiden integer joins and the callable-value arity ladder, neither plausibly this repair), and frankZ could not make the observable appear on pin v408 either -- a compiler that PREDATES the likely closers `575e9ec16` and `5445b96d8` and should have held the defect. So the observable is gone and the MECHANISM WAS NEVER RE-ESTABLISHED. Closing on the corpus that reported it, not on a cause. If this shape ever regresses, do not start from the probe list in this ticket -- every one of those passed on the known-bad compiler too."
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

**ASKED, NOT MEASURED — 2026-09-13, frankZ to frankh-30.** Rather than write a
tenth probe, I asked the seat that got lekkerzeilen running today whether the
demo still exercises the same-name `from .platform import gl` seam unmodified,
and whether the 117 `gl.<method>()` calls this ticket cites actually execute
now. A yes closes this on the corpus rather than on a probe; a "the seam was
renamed/rerouted" means the corpus no longer exercises the failing shape and
this stays open with that noted. **No answer yet at the time of writing** — if
you are reading this and no verdict has been appended below, the question is
still outstanding and asking again is cheaper than re-probing.

## RESOLVED 2026-09-13 — THE CORPUS ANSWERS ITS OWN REPRO

Asked rather than probed. frankZ asked frankh-30, who got the demo running
today, whether the seam still uses the same-name form and whether the calls
execute. It does, and they do.

**What I verified myself, reading `/home/neo/lekkerzeilen` at its working tree
(the owner's, with the owner's own uncommitted edits in it — `git log -1` is
`9521e53`, 2026-09-12, and `__main__.py`, `gfx.py`, `capture.py` and
`platform/__init__.py` all carry unstaged modifications, so "unmodified" here
means frankh-30 changed nothing, NOT that it matches a commit):**

- `platform/_pxx.py:139` — `class gl:`; `get_string` at `:480` is a
  `@staticmethod` inside that class body. 91 `@staticmethod` in the class.
- `platform/__init__.py:86` — `gl = _backend.gl`, where `_backend` comes from a
  guarded import: `try: import ctypes` / `except ImportError: from . import _pxx
  as _backend`. Under pxx, ctypes is absent, so the pxx backend is the one bound.
- Same-name from-imports, no rename anywhere: `gfx.py:10`, `capture.py:13`,
  `__main__.py:46` (a multi-name list ending in `gl`), `app.py:26` (likewise).
- `__main__.py:159-160` and `app.py:4409-4410` — `gl.get_string(gl.RENDERER)`
  and `gl.get_string(gl.VERSION)`, i.e. this ticket's repro with a constant read
  through the same class value in the same expression.

**What rests on frankh-30's run, not on my reading:** the printed output
`gl       : 3.3.0 NVIDIA 580.178.04`, the render loop reaching a GL 3.3 context
and a loaded world, and the 148 `gl.` occurrences in gfx.py executing rather than
merely compiling.

**The pxx-versus-CPython discriminator, because a green here could have been
correct about a different interpreter.** Two independent tells, and I checked the
second myself: the demo now dies much later in `Vessel.fittings_data` on a NilPy
lowering defect (a module-qualified def returning a container, read as a value),
which CPython cannot produce; and `bin/` holds four pxx-built binaries from this
evening (`lz_h1` 18:55 through `lz_h4` 19:24) whose `.map` files begin
`# Frankonpiler Map File` and whose ELF has no section header — pxx's own writer.
The run is our compiler.

**Repair not attributed, and that is deliberate.** frankh-30's two commits today
(`fec1abd13`, nine of eleven machine integer kinds had no join in `PyWiden`;
`2b7068dd7`, the callable-value ladder to eight arguments plus an arity refusal
naming the callee) are not plausibly this fix, and they said so unprompted. The
likely closers remain `575e9ec16` and `5445b96d8`. Nobody has bisected it and
this ticket does not claim one.

**The residual, and it is the honest half.** I could not make this observable
appear on pin v408 — which predates both likely closers and should have held the
defect — across nine shapes including a full package mirroring this exact seam.
So my reconstruction never captured the failing condition, and the corpus can
only say the shape WORKS NOW. It cannot say what was broken, or what fixed it.
Closing on the observable in the tree that reported it, with the mechanism
unestablished. See CLAUDE.md, "isolation guards the RUN, not the ROUTE".

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit af9d8c723.
