---
track: N
prio: 55
type: bug
blocked-by: []
summary: "`from pkg import NAME` fails with `undefined variable (NAME)` when pkg's `__init__.py` obtained NAME by importing it, rather than defining it. Flat unit scope: a module's imports do not join what it re-exports. This is how nearly every real package publishes its public API, so it blocks the third-party corpora one rung past relative imports."
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
