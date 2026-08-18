---
track: N
prio: 90
type: bug
blocked-by: []
summary: "Calling an IMPORTED function or method and omitting a defaulted parameter silently passes None/0 instead of the default. `plainmod.withdef(1)` returns None where CPython returns 7; two defaults returns 0 where CPython returns 16; an imported class's method behaves the same. Exit 0, no diagnostic, no crash. The same call in the SAME file is correct, and supplying the argument explicitly is correct. The already-filed alias segfault is one symptom of this, not the whole bug."
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
