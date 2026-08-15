---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`class Codec(codecs.Codec): pass` — a NilPy class whose own name equals its imported base's name — makes the compiler LOOP FOREVER. No diagnostic, no progress, no timeout. Four lines reproduce it, and it is the canonical spelling of every codec module in CPython's stdlib."
status: done
owner: agent-an-night
---

# `class X(mod.X)` hangs the compiler

Found porting the `codecs` shim for [[feature-b-mimic-codecs-for-nilpy]],
against `stable_linux_amd64/default/pinned` **v339 /
f11e0ed9816edc1d57ef8ee6e6ab0e5b9885db6c**.

## Repro

```python
import codecs


class Codec(codecs.Codec):
    pass
```

The compiler never returns. Killed at 25s, 60s and 120s; no output beyond the
shim note, no error, no partial binary.

## The controls that say exactly what it is

| source | result |
| --- | --- |
| `class Codec(codecs.Codec)` | **HANGS** |
| `class MyCodec(codecs.Codec)` — different name, same base | compiles |
| `class MyCodec(codecs.Codec)` with a method also named `encode` | compiles |
| `class PBase(probeu.PBase)` on a hand-written Pascal unit | **HANGS** |
| `class Other(probeu.PBase)` on the same unit | compiles |

So it is neither shim-specific nor method-name-related: the single trigger is
**the derived class having the same name as its base**, which the flat namespace
then presumably resolves back to the class being declared — a cycle nothing
breaks.

## Why this one matters more than its size suggests

`class Codec(codecs.Codec)` is not a corner case someone contrived. It is how
**every** codec module in CPython's own stdlib is written, and how
`webencodings/x_user_defined.py` — the bottom rung of the
webencodings -> tinycss2 -> html5lib ladder in
[[feature-nilpy-thirdparty-libraries-as-targets]] — is written. Python's
per-module namespace makes reusing the base's name the natural choice, so real
library code does it constantly.

And a **hang is the worst failure mode available**. A wrong answer can be
diffed, an error can be read; an infinite loop in the compiler looks like a slow
build, and the first thing anyone does is wait longer. A cycle guard that
reported "class X cannot inherit from itself" would already turn this from a
mystery into a one-line fix at the call site.

## Fix shape

Whatever resolves a NilPy base-class name must resolve it **in the scope the
base was named in** — `codecs.Codec` is qualified, so the answer can never be
the class currently being declared — and, independently, the resolver walk needs
a visited-set or depth cap so that a cycle from any other cause reports instead
of spinning. Both, not either: the qualified-lookup fix is the correct
semantics, and the guard is what stops the next cause being another hang.

## Blocks

The `x_user_defined.py` half of [[feature-b-mimic-codecs-for-nilpy]]'s gate.
That file also needs multiple inheritance from an imported base
([[bug-nilpy-multiple-inheritance-from-an-imported-base-is-refused]]), so it
needs both before it compiles; `mimic_codecs` itself is unaffected and lands.

## Resolution (2026-08-15)

Root cause was NOT in the base-name lookup — it was in **class registration**,
one level under it. NilPy's shell pre-pass (`PyRegisterClassShells`) registers a
FORWARD row per `class X` in the .npy *before any import is parsed*. The Pascal
class-declaration path then reuses a forward row of the same name — and that
reuse was **unit-blind**. So the imported unit's `type PBase = class` filled the
PROGRAM's stub instead of allocating its own row: the NilPy class and its
intended base were literally one row, `UClsParent[ci] := ci`, and the ancestor
walk spun.

Measured, not reasoned: a probe over the `UCls` table showed exactly ONE row
named `PBase` (unit -1) in the colliding case, and TWO rows when the NilPy class
was renamed `Q` — the imported unit only got a row when the names differed.

Three changes, all needed:

1. `parser.inc` — a forward stub is filled only by its **own** unit:
   `UClsForward[ci] and (UClsUnitIdx[ci] = CurrentUnitIdx)`. A stub belongs to
   the unit that wrote it; otherwise two unrelated classes merge into one row.
   This is the real fix, and it is not NilPy-specific.
2. `pyparser.inc` — a QUALIFIED base resolves in the named module
   (`FindUClassInUnit(name, baseQUnit)`), so a same-named class being declared
   here can never be the answer. `ConsumeUnitQualifier` captures the qualifier
   before the dotted path is consumed.
3. `pyparser.inc` — the cycle guard the ticket asked for, independent of both:
   `baseCi = ci` or `PyClsHasAncestor(baseCi, ci)` now reports
   "class X cannot inherit from itself" instead of spinning. Checked against the
   whole ancestor chain so a future cause reports too.

Tests: `test/test_nilpy_class_named_after_its_imported_base.npy` +
`test/nilpy_units/samenamebase.pas` (override dispatches, the base's own method
is inherited, and the unit's class is still constructible on its own), and
`test/test_nilpy_class_inherits_itself_fail.npy` for the guard. Wired into both
`test-nilpy` and `test-core`.

Gate: `make compiler/pascal26` (fixedpoint) + repro + `tools/gate.sh quick`
GREEN, FPC seed canary included.

## Log
- 2026-08-15 — resolved, commit 5fd842e6a.
