---
track: N
prio: 90
type: bug
blocked-by: []
summary: "Calling an IMPORTED function or method and omitting a defaulted parameter silently passes None/0 instead of the default. `plainmod.withdef(1)` returns None where CPython returns 7; two defaults returns 0 where CPython returns 16; an imported class's method behaves the same. Exit 0, no diagnostic, no crash. The same call in the SAME file is correct, and supplying the argument explicitly is correct. The already-filed alias segfault is one symptom of this, not the whole bug."
status: done
owner: frank2-7e
---

# A default argument is dropped on every cross-module call

- **Type:** bug — **Track N** (Nil-Python frontend / lowering).
- **Found:** 2026-08-18 by frank3-fc, sweeping `lib/rtl/mimic_*.py` for the
  shape in [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]].
- **Measured against:** `pinned` **v348** (`6214284a91ca`, pin commit `f5d85953a`).
- CPython accepts and runs every line below, so this is a defect, not a dialect
  choice.

## Repro

`plainmod.py`:

```python
def withdef(a, lo=7):
    return lo

def twodef(a, lo=7, hi=9):
    return lo + hi

class C:
    def m(self, a, lo=7):
        return lo
```

```python
import plainmod
print(plainmod.withdef(1))     # prints None    -- CPython prints 7
print(plainmod.twodef(1))      # prints 0       -- CPython prints 16
```

**Exit 0. No diagnostic. No crash.** The value is simply wrong.

## The boundary, one variable at a time

| call shape | result | correct |
| --- | --- | --- |
| same-file `f(1)` with `lo=7` | 7 | ✅ |
| same-file method `C().m(1)` | 7 | ✅ |
| `from M import f` then `f(1)` | 7 | ✅ |
| **`import M` then `M.f(1)`** | **None** | ❌ |
| **`import M as m` then `m.f(1)`** | **None** | ❌ |
| **`from M import f as g` then `g(1)`** | **segfault** | ❌ |
| **`from M import C` then `C().m(1)`** | **None** | ❌ |
| two defaults omitted, cross-module | **0** (or segfault) | ❌ |
| any of the above with the argument supplied explicitly | correct | ✅ |
| imported function with **no** defaulted parameters | correct | ✅ |

So the discriminator is not the alias and not the qualification — it is
**crossing a module boundary while letting a default apply.** The defaults
appear not to travel with the imported symbol, so the call site passes fewer
arguments than the body reads and the missing ones arrive as None / 0 /
whatever was there.

That paragraph is a reading of the table, not a measurement of the lowering.

## Relationship to the alias ticket

[[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]
(p70) is a **symptom of this**, not a separate fault: the alias cases are the
sub-rows above where the garbage happens to get dereferenced. That ticket's own
boundary work already found the silent-wrong variant at one default. This
ticket is the general statement; fixing this should close that one, and the
alias ticket's repro is worth keeping as a regression test because the crashing
shape is the one that fails loudly.

## Why p90 and urgent

- **Silent wrong values in the most ordinary Python spelling there is.**
  `import M` / `M.f(x)` is how every multi-module Python program is written.
- Nothing warns. Exit code 0. A program built on it produces plausible output.
- It scales with the size of the program: single-file tests are all correct, so
  the test suite is systematically blind to it — every `.npy` test that passes
  today may be passing *because* it is one file.
- The corpora are multi-module by definition, so every "it compiles now" result
  on the third-party ladder is a claim about compilation only, and any RUN of
  those libraries is suspect until this lands.

## What to check when fixing

Verify by **value**, cross-module, for: a function default, a method default,
several defaults where only some are omitted, a default that is a string or a
tuple rather than an int (None-shaped garbage may read as a plausible empty
value), and a keyword argument passed by name out of order. The single-file
control passing is not evidence of anything here.

---

## Coordinator verification 2026-08-18 — confirmed against the CPython oracle

Reproduced independently at HEAD, differential against CPython on the same source file
(the `.npy` is run by `python3` unmodified), module named lowercase to avoid the
unrelated unit-name-case confound:

```python
# mmod.py
def f(a, lo=7):        return lo
def g(a, lo=3, hi=13): return lo + hi
class C:
    def m(self, a, lo=7): return lo
```

| call | pxx | CPython | |
| --- | --- | --- | --- |
| `from mmod import f; f(1)` | 7 | 7 | ok |
| `import mmod; mmod.f(1)` | **None** | 7 | **DIVERGES** |
| `import mmod as m; m.f(1)` | **None** | 7 | **DIVERGES** |
| `from mmod import C; C().m(1)` | **None** | 7 | **DIVERGES** |
| `import mmod; mmod.g(1)` (two defaults) | **0** | 16 | **DIVERGES** |
| `import mmod; mmod.f(1, 3)` | 3 | 3 | ok |

Exit 0 throughout, no diagnostic. Confirms the filed boundary exactly: the defect is
crossing a module boundary while letting a default apply, and `from X import f` is the
one form that survives.

### The suite-blindness claim, measured

The ticket argues the `.npy` suite cannot see this because single-file programs are all
correct. Measured statically, and it holds:

```
716   .npy tests in test/
 10   sibling .py modules in test/
```

So at most ~10 of 716 tests can exercise a call into a **user** module at all — the 80
files using bare `import X` are overwhelmingly importing stdlib names and shims, not
local siblings. Coverage of this shape is close to nil, which is consistent with a defect
this broad surviving unnoticed.

### Consequence for the corpus numbers, and this is the part to carry

Every "N/48 compiles" figure this campaign has published — including today's 6/48 — is a
claim about **compiling**, not about running. The corpora are multi-module by
construction, so the shape this bug breaks is the shape they are made of. **No ladder
number should be read as "the library works"** until this lands. That is not a caveat on
one report; it applies retroactively to every ladder A/B in
[[feature-nilpy-thirdparty-libraries-as-targets]].

The alias-default ticket
(`bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults`, p70) is a
SYMPTOM of this one — the alias rows are where the dropped default happens to get
dereferenced instead of silently substituted. Keep its repro as a regression test, since
a crash is the shape that fails loudly, but fix it here.

## FIXED 2026-08-18 (frank2-7e, combined A+N)

### Root cause — an over-broad predicate, measured before it was touched

`DefaultArgValueNode` (`compiler/parser.inc`, ~2988):

```pascal
else if isNilPy and (Procs[mpi].Params[k].TypeKind = tyVariant) and
        (ProcParamDefaultIsNone[mpi * MAX_PROC_PARAMS + k] or
         (ProcUnitIdx[mpi] >= 0)) then
  exprNode := PyMakeNone
```

`ProcUnitIdx[mpi] >= 0` means "this routine lives in another unit", and it forced
the None path **regardless of the declared default**.

Confirmed with a probe before editing, rather than read off the source — the
declared value is present and correct and is simply discarded:

```
PXXDBG n.defarg proc=f k=1 unitidx=612 tk=22 isnone=FALSE sym=-1 val=7 isNilPy=TRUE
                          ^^^^^^^^^^^^ forces None            ^^^^^ the right answer
```

**The clause is deliberate and load-bearing, not an oversight.** Its comment says
why: a `lib/pcl` Pascal façade declares `const opt: Variant = 0` as a SENTINEL
meaning "not supplied", and 26 call sites across `lib/pcl` test `pyvartag(v) <> 0`
to find out. Boxing that 0 as an integer made an omitted option look GIVEN —
`canvas.configure(yscrollcommand=...)` passed a filled `xscrollcommand` and
tkinter refused it.

So `ProcUnitIdx >= 0` was standing in for *"this is a Pascal library façade"*, and
a user's imported `.py` module satisfies the proxy while needing the opposite
answer. A fact inferred from a proxy instead of recorded.

### Fix — record the fact

A per-unit "this unit is a NilPy module" marker on the existing
`CTUnitIdx` / `UnitIsCTranslationUnit` pattern: `PyModUnitIdx` in `defs.inc`,
`UnitIsPyModule` / `MarkUnitPyModule` in `symtab.inc`, set in `ParsePyUnit`. The
predicate then reads `(ProcUnitIdx[mpi] >= 0) and not UnitIsPyModule(...)`.

A **parallel array, not a `TProc` field** — a new field there is the known
self-host landmine (`project_tsymbol_field_landmine`), and the C-translation-unit
list next to it already uses this shape.

### Verified by VALUE against CPython, every shape the ticket asked for

| call | before | after | CPython |
| --- | --- | --- | --- |
| `import M; M.f(1)` | None | **7** | 7 |
| `import M as m; m.f(1)` | None | **7** | 7 |
| `import M; M.g(1)` (two defaults) | 0 | **16** | 16 |
| `import M; M.g(1, 5)` (only some omitted) | 5 | **18** | 18 |
| `from M import C; C().m(1)` | None | **7** | 7 |
| `M.s(1)` (**string** default) | dflt | dflt | dflt |
| `M.f(1, 3)` (supplied) | 3 | 3 | 3 |

The string default was **already correct**, which is diagnostic rather than
incidental: `ProcParamDefaultIsStr` is tested *before* the variant branch, so only
variant-typed parameters were ever affected.

### The façade behaviour is NOT regressed

The risk in this fix was trading a silent NilPy bug for a silent tkinter one. The
three tk examples exercise `configure()` with omitted options and now actually RUN
under Xvfb (`5215148bb`): `tkinter_facade`, `field_class_identity` and `callbacks`
all still match their `.expected` byte for byte.

### Regression test

`test/test_nilpy_cross_module_defaults.npy` + `test/nilpy_units/defmod.npy`, wired
into `test-nilpy` by name (the suite enumerates and never globs). Verified both
ways: on pinned v348 it prints `None / 0 / 5 / 3 / dflt / None`, at HEAD
`7 / 16 / 18 / 3 / dflt / 7`.

**Why the suite could not see this**, now covered: it needs a `.py` callee, a
variant parameter and an omitted argument *at once*. A Pascal-callee test would
have passed — `import pasmod; pasmod.pf(1)` with `lo: Integer = 7` is correct
today and always was, because an Integer parameter never reaches the branch.

### Two OTHER bugs found here — this ticket does NOT retire the alias one

1. **[[bug-n-an-import-alias-binds-to-a-same-named-member-of-the-source-module]]**
   (filed, N p85). `from mmod import f as g` binds `g` to mmod's own `g`:
   `g(1, 5)` gives 18 with **every argument supplied**, so no default is
   involved. Aliasing to a name that is a CLASS in the module constructs that
   class instead. Independent of this ticket and unaffected by this fix.

2. **Calling through a function-VALUED name still drops defaults** — and its
   scope is wider than
   [[bug-n-calling-through-a-function-alias-with-a-default-omitted-segfaults]]
   states. `from M import f as zz; zz(1)` is still wrong after this fix, and so
   is a plain **same-file** `zz = loc; zz(1)`. So it is not about imports or
   module boundaries at all: a call through a procedural value does not consult
   the callee's defaults. That ticket stays open and should be re-scoped.

### Gate

`make compiler/pascal26` (fixedpoint, converged) + the value table above + the tk
façade check + the new test failing pre-fix and passing post-fix +
`tools/gate.sh quick` GREEN (FPC seed canary included — this adds a routine and a
parallel array). No pin needed; nothing in `compiler/builtin/**`.

## Log
- 2026-08-18 — resolved, commit 3d66bdff7.
