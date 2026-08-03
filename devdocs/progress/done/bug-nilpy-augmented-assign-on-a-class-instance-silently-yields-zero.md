---
track: N
prio: 45
type: bug
summary: "`obj += n` on a class instance silently produces 0 — neither __iadd__ nor the __add__ fallback is dispatched, and nothing raises"
status: done
owner: claude-AN
---

# `obj += n` on a class instance silently yields 0

- **Type:** bug (NilPy, silent wrong answer) — **Track N**
- **Found:** 2026-08-03, by running the reproducer in
  [[feature-nilpy-arithmetic-dunders-full-protocol]] and finding that ticket's
  subject already works. This is the part that does not.

## Measured

```python
class C:
    def __init__(self, v: int):
        self.v = v

    def __add__(self, o):
        return C(self.v + o)

    def __iadd__(self, o):
        return C(self.v + o)


d = C(1)
d += 5
print(d.v)          # CPython: 6      pxx: 0
```

`0`, not an error. Identical with **only** `__add__` declared (CPython falls
back to `__add__` and rebinds the name, giving 6; pxx still gives 0), so this
is not specifically an `__iadd__` gap — the augmented-assignment path on a
class-typed target does not reach either dunder, and whatever it does produce
leaves the target holding zero.

## Why this is filed apart from its parent

`feature-nilpy-arithmetic-dunders-full-protocol` is a 195-line phase-2 feature
ticket, and the rest of it has since landed: `__add__`, `__sub__`, `__mul__`,
`__truediv__`, `__floordiv__`, `__mod__`, `__pow__`, the mixed-type form
(`c + 3`) and the reflected form (`3 + c`) were all measured correct against
CPython in the same pass. Leaving a **silent wrong answer** as one unmarked
line inside a mostly-done feature ticket is how it stays invisible; the
severity here is not "feature incomplete", it is "a normal Python idiom
computes 0 and says nothing".

The failure direction is the bad one — a counter or accumulator built with
`+=` on an instance reads as zero rather than failing, so the program produces
plausible wrong output with no diagnostic.

## Fix direction

Not investigated. The starting point is NilPy's augmented-assignment lowering
(`PyAugBinTok` and the two augmented-assign sites in `pyparser.inc`, which
build an `AN_BINOP` from the target and the operand): a `tyClass` target
presumably falls into the numeric path and the binop yields a handle/zero
rather than dispatching. Python's own rule is `__iadd__` if declared, else
`__add__` then rebind, so both need to route through the same dispatch the
plain `a + b` expression path already uses correctly.

## Gate

A `.npy` diffed against CPython: `+=` with `__iadd__` declared, with only
`__add__` declared, and the same for `-=`/`*=`/`/=`/`//=`/`%=`/`**=`; plus a
class with neither, which must RAISE rather than answer 0; and the existing
plain-binop dunder cases still green.

## Fixed 2026-08-03

`PyAugClassDunder` (pyparser.inc), applied in the augmented-assignment path
after the existing TPyList `+=`-is-extend case, implements Python's actual
rule for a user-class target:

1. the **in-place** dunder if declared (`__iadd__`, `__isub__`, …);
2. otherwise the **binary** one (`__add__`, …), rebinding the name with its
   result — which is why the bug reproduced with only `__add__` declared;
3. otherwise a genuine runtime **TypeError**.

Operator→dunder mapping is `PyAugDunderName`, keyed on the BINARY token
`PyAugBinTok` already produced rather than on the augmented token — so NilPy's
`//=`-is-`tkDiv` / `/=`-is-`tkSlash` split (the reverse of Pascal's reading of
the same token, see the frontend-collision note) is honoured in one place
instead of being re-derived.

### The third case is the one that was nearly missed

The first cut fell THROUGH when neither dunder existed, which left that shape
still answering 0 silently — the same bug, just narrower. It now raises
`PyUnsupportedOperandError`, an EXISTING pylib raiser (deliberately: adding a
new one would mean a `compiler/builtin/**` change and therefore a
stabilize+pin). Raised at RUN time, not via the compiler's `Error()`, so
`try/except TypeError` around the statement still compiles and runs its handler
— the same shape every other missing-dunder site in this frontend uses, and
verified in the test.

### Verified

`test/test_nilpy_augmented_assign_class_dunder.npy` (new, both `test-nilpy`
Makefile sites), byte-identical to CPython: `+=`/`-=`/`*=`/`//=`/`%=` with
in-place dunders; `+=`/`*=` with only the binary dunder declared; the
accumulate-in-a-loop idiom the silent 0 was hiding in; the neither-declared
case inside a `try/except TypeError` that must run its handler; and two
regressions that must NOT change — a plain int `+=` accumulator, and a list
`+=` staying in-place extend (both aliases see it).

`tools/gate.sh quick` GREEN (self-host fixedpoint + `--tier quick` + FPC seed
canary).

### Scope — the FIELD target is NOT fixed, and here is what was measured

This fixes the NAME-target path (`obj += n`). A FIELD target still answers 0
silently: `h.acc += 5` prints 0 where CPython prints 15.

A fix for it was written (dispatch off the lhs-expression augmented-assign site
in `PyParseStatement`, with the target CLONED rather than shared so the receiver
is not evaluated twice) and then **backed out, because it never fired** — a
probe in the dispatch function produced no output at all for `h.acc += 5`, so
the statement does not reach that site. Shipping a branch that never executes
would have read as coverage that does not exist.

The remaining work is therefore **first to find which path actually handles an
augmented assignment to a field**, not to write the dispatch again. Filed on as
[[bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero]].

## Log
- 2026-08-03 — resolved, commit 8b694981c.
