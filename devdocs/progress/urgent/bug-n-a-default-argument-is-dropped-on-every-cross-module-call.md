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
