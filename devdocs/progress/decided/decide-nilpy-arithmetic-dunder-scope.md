---
track: U
prio: 60
type: decide
status: resolved
resolved: 2026-08-01
---

## DECIDED 2026-08-01 — phased: option 3 first, option 1 later

**User's call.** Comparisons first (no collision risk, covers the common
`sorted()`/`min()`/`max()` case), full arithmetic protocol later, one
operator at a time (real collision risk with pathlib and similar
special-cased routes — confirmed "quite big work"). Filed as
[[feature-nilpy-arithmetic-ordering-dunders]] (umbrella) with
[[bug-nilpy-comparison-dunders-not-dispatched]] (phase 1, ready now) and
[[feature-nilpy-arithmetic-dunders-full-protocol]] (phase 2, after phase 1).

# Decide: how far does NilPy follow Python's arithmetic/ordering dunder protocol?

Split out of [[bug-nilpy-dunder-protocols-ignored-fall-back-to-handle-arithmetic]],
whose four sub-clusters are otherwise done this session (`__len__`,
`__contains__`, `__call__`, `__getitem__`/`__setitem__` all landed and
dispatch to the user method now, raising a genuine runtime TypeError rather
than silently reading the instance pointer as a number when neither dunder
exists).

## The fork

```python
class C:
    def __init__(self, v):
        self.v = v
    def __add__(self, o):
        return self.v + o.v
print(C(1) + C(2))     # CPython: 3     pxx: 268329319137376 (adds the HANDLES)
```

`C(1) + C(2)` is two STATICALLY `tyClass` operands, so it takes the raw
`IR_BINOP` path and adds the raw instance pointers — silently, no error, a
different plausible number every run. Same shape for `__sub__`/`__mul__`/etc.
and the ordering dunders (`__lt__`/`__gt__`/…, reached via `sorted`/`<`/`>`).

Fixing this is NOT a narrow, contained change like the four already-landed
protocols, because of one hazard the ticket already flagged:

**`IRPyNumStrClash` / the class-operand question.** The str-vs-number clash
check that already exists for `+` deliberately only fires for a
str-vs-number PAIR. Extending it to ANY class operand is not safe: some
class pairs on `+`/`/`/etc. are ALREADY legitimate and special-routed
(`Path("a") / "b"` is pathlib's join). A blanket "any class operand on `+`
checks `__add__` first" rule has to be threaded through every arithmetic
AND comparison operator, and has to compose with whatever ELSE already
special-cases a class operand on that operator, without breaking any of
those existing special cases.

## Options

1. **Full protocol** — dispatch every binary arithmetic op (`+ - * / // % **`)
   and every comparison (`< <= > >= == !=`) to the matching dunder
   (`__add__`/`__radd__`, `__lt__`, …) when the operand's class defines it,
   falling back to today's behavior (or a loud error) otherwise. Matches
   Python exactly; largest surface, most collision risk with existing
   special-cased class-operand routes (pathlib, others).
2. **Narrow scope to what's actually hit** — census which of these a real
   corpus (uforth, songformatter, the fpjson/OOP suites) actually uses, and
   wire only those. Smaller, faster, but leaves a known gap for anything not
   censused (the SAME "silent wrong value" bug for an uncensused operator).
3. **Comparison operators only** (`__lt__`/`__eq__`/`__gt__`/…, no
   arithmetic) — `sorted()`/`min()`/`max()` on custom-ordered objects is the
   most common real use of dunder protocols beyond what's already fixed, and
   ordering ops don't have the pathlib-style existing-special-case collision
   arithmetic ops do (nothing today special-cases `<`/`>` on a class pair the
   way `/` is special-cased for pathlib).
4. **Accept and document** — leave arithmetic/ordering on class operands as a
   known, documented "not supported, will silently compute the wrong thing"
   gap, and put effort elsewhere. Weakest: this is exactly the "expensive
   bug" class (plausible wrong value, no diagnostic) the project's own
   debugging playbook singles out.

Recommendation: 3, then 1 if there's appetite — comparisons alone avoid the
pathlib-style collision risk entirely (nothing special-cases `<`/`>` on a
class today) while covering the single most likely real use
(`sorted(objs)`/`min(objs)`/`max(objs)` on a custom-ordered type), and is a
natural extension of the `sorted(key=...)` work already landed
([[bug-nilpy-callable-value-abi-sorted-key-and-builtins]]). Arithmetic
dunders (option 1's other half) can follow once the pathlib-collision
question is worked out per-operator.

## Gate (once scope is decided)

`make test-nilpy` + self-host byte-identical, plus a `.npy` per dunder
covered, diffed against CPython. A class operand on an operator with NO
matching dunder must raise a genuine runtime TypeError (matching the
pattern PyNotContainerError/PyNotCallableError/PyNoSetitemError already
established), not silently compute off the handle.
