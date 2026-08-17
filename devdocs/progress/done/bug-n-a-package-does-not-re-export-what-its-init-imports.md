---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from pkg import NAME` fails with `undefined variable (NAME)` when pkg's `__init__.py` obtained NAME by importing it, rather than defining it. Flat unit scope: a module's imports do not join what it re-exports. This is how nearly every real package publishes its public API, so it blocks the third-party corpora one rung past relative imports."
status: done
---

# A package does not re-export what its `__init__.py` imports

- **Type:** bug (NilPy frontend, module/unit scope) — **Track N**.
- **Found:** 2026-08-17, immediately after
  [[bug-n-relative-import-from-a-package-is-not-parsed]] was fixed — it is the
  next wall on the same five-line repro, and it is what that ticket's original
  repro was really asserting.

## Repro

```
pkg/sub.py        VALUE = 7
pkg/__init__.py   from .sub import VALUE
main.npy          from pkg import VALUE
                  print(VALUE)
```

| | |
| --- | --- |
| CPython | `7` |
| pxx | `pascal26:2: error: undefined variable (VALUE)` |

At least it is a loud failure, not a wrong value.

## Two controls, and they are what identify the mechanism

| `pkg/__init__.py` contains | `from pkg import VALUE` |
| --- | --- |
| `VALUE = 7` (**defined** here) | **works** |
| `from .sub import VALUE` (**imported**, relative) | fails |
| `from sub import VALUE` (**imported**, absolute) | fails, identically |

So it is neither the dot nor the package layout: **a name a module imports does
not become part of what that module publishes.** Names it defines do.

Within `__init__.py` itself the imported name is perfectly usable — verified:

```
pkg/__init__.py   from .sub import VALUE
                  Y = VALUE * 2          # main gets Y == 14, correct
```

which pins the defect to the boundary crossing, not to the import.

## Mechanism, as far as it was traced

NilPy unit scope is flat: `from X import a, b` calls `ParseUsesUnit(X)` and
lets the names resolve unqualified, rather than binding them into the importing
module (see the comment at `pyparser.inc:~31752`). That is a deliberate design
and it works fine *within* one compilation of one module. What it does not
produce is a re-export: `pkg` has no namespace of its own into which `sub`'s
names were copied, so an importer of `pkg` asking for `VALUE` finds nothing —
`VALUE` lives in unit `sub`, which the importer never named.

**Not investigated:** whether the honest fix is to make a module's from-imports
also register in the importing unit's own scope, or whether `from pkg import X`
should fall back to searching the units `pkg` itself pulled. The second sounds
cheaper and is probably wrong — it makes every import transitively public,
which is the opposite of what `__all__` exists for. Pick deliberately;
[[devdocs/dev/root-cause-over-microfix.md]] applies, and this touches how every
NilPy module boundary works.

## Why it matters now

This is the **standard way a Python package publishes its API**: the modules
are private, `__init__.py` imports the public names out of them, and consumers
import from the package. `webencodings/__init__.py` does exactly this with
`lookup`/`decode`/`encode`; so do `tinycss2` and `html5lib`. Relative imports
were the first rung of [[feature-nilpy-thirdparty-libraries-as-targets]] and
this is the second — a corpus driver that does `from webencodings import
lookup` meets it as soon as the file compiles.

It is also a good example of the campaign's own premise: no `.npy` test we
wrote ourselves would have found it, because a single-file test has no package
boundary to cross.

## Gate

`make compiler/pascal26` + the repro above answering `7`, + the control table
above unchanged (especially: a name DEFINED in `__init__.py` must still
re-export), then `tools/gate.sh quick` **before committing** so the FPC seed
canary runs. Extend `test/test_nilpy_relative_import_in_package.npy`, which
today deliberately reads only names its `__init__.py` defines, and says so.

Stretch check: a driver doing `from webencodings import lookup` gets past the
import.

---

## FIXED 2026-08-17 — it was a missing BINDING, not a visibility rule

The "not investigated" fork above is settled, and it did not need a decision
ticket in the end because a measurement chose between the two options outright.

**The deciding observation:** an *aliased* re-export already worked.

```
pkg/__init__.py   from .two import A as AA      ->  `from pkg import AA`  WORKS
pkg/__init__.py   from .two import A           ->  `from pkg import A`   FAILED
```

Same units, same visibility, opposite results — so visibility was never the
variable. The alias path desugars to `ALIAS = NAME`, which creates a **real
symbol in the importing unit**; the plain path creates nothing and leans on flat
unit scope, which stops at the first module boundary. The name simply was not
`pkg`'s to publish.

That rules out the second option (searching the units `pkg` itself pulled) on
its merits rather than on taste: it would have made every import transitively
public, and it would not have explained why the aliased spelling behaved
differently. It also avoids touching `VisibilityAllows`, whose non-transitive
one-hop rule the user set deliberately (2026-08-15) and which is Track A ground.

### The fix

`from mod import NAME` now queues the same binding the `as` form does, so the
name becomes the importing module's own — which is also exactly CPython's
semantics: a from-import **binds a name in the importer's namespace**, it does
not open a window onto the exporter's. Flat unit scope had been standing in for
that binding all along.

**Scoped to MODULES (`CurrentUnitIdx >= 0`), deliberately.** The main program
has no importers, so a binding there re-exports to nobody while adding a symbol
that shadows the flat-scope resolution every existing NilPy program relies on.
That is blast radius with no measured demand. Recorded as a scope choice, not an
oversight: if a case ever needs it in the program too, the condition is one term.

Rides on the flush fix from
[[bug-n-from-import-as-alias-binds-zero-inside-a-pulled-module]] — without a
module flushing its own alias queue, this would have queued bindings that never
materialised and turned a loud `undefined variable` into a silent 0. **The order
mattered; the two are one mechanism and landed together.**

### Verified — nine probes, all matching CPython

The ticket's own five-line repro answers `7`. The control table above holds in
every row, including the ones that must NOT change (a name DEFINED in
`__init__.py` still re-exports; the top-level program is untouched). Bare-dot,
multi-name, `as`, qualified access and two-level packages all agree with
CPython.

`webencodings/__init__.py` is unmoved at line 50 (`codecs.CodecInfo`), which is
the expected result — that is the Track B `mimic_codecs` rung, and it confirms
this fix did not shift the wall it was not aiming at.

### Still open, found by the two-level probe and NOT part of this

`from .subpkg import X` where `subpkg` is a DIRECTORY with its own
`__init__.py` reports `no unit named inner`. Sub-PACKAGE resolution is a
separate mechanism from sub-MODULE resolution; html5lib has real subpackages
(`_trie`, `treebuilders`, `treewalkers`), so this will be the next rung there.
Filed as [[bug-n-a-subpackage-directory-does-not-resolve-as-a-module]].

## Log
- 2026-08-17 — resolved, commit 8548f98d8.
