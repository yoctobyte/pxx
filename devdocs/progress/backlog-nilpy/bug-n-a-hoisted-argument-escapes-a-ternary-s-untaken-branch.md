---
slug: bug-n-a-hoisted-argument-escapes-a-ternary-s-untaken-branch
title: a hoisted argument escapes a ternary's untaken branch
summary: >
  `f(*[track(10), track(20)]) if c else 99` with c False evaluates BOTH
  track() calls; CPython evaluates neither. The star machinery lowers its
  operand into hoisted statements (PyHoistStmt), and the hoist lands at the
  enclosing STATEMENT, not inside the conditional arm the call sits in -- so
  every construct in this frontend that hoists has the same escape. Found while
  deciding whether the run-time dynamic-dispatch path could route every arity
  through a hoisted TPyList; it cannot, and that decision is now documented in
  PyMakeDynMethCall as the reason the small arities keep their direct rungs.
  Fixing this is what would let those two paths merge.
track: N
type: bug
prio: 80
owner: unassigned
status: open
---

## Measured 2026-09-13, at `533c194fd`, no dynamic dispatch involved

```python
calls = []

def track(v):
    calls.append(v)
    return v

def f(a, b):
    return a + b

c = False
r = f(*[track(10), track(20)]) if c else 99
print(r, calls)
```

| | result |
| --- | --- |
| CPython | `99 []` |
| pxx | `99 [10, 20]` |

The VALUE is right in both. Only the side effects differ, which is why no
`expect_same` row over `r` could ever have caught it — the instrument has to be
a log of what RAN, not of what was returned. Same structural blindness as
CLAUDE.md's leak and store-order rows.

## Why it matters beyond a probe

Two callers pay for it today and both are ordinary Python:

- A star-unpacked call in a conditional expression — the row above.
- Any construct whose desugar hoists. `enumerate(xs, start=bump())` binds its
  start to a hidden local before the loop *deliberately* (once, not
  per-iteration), and that hoist is correct because a `for` header always runs.
  A hoist inside a ternary arm is the same mechanism where the arm may not.

## A THIRD INSTANCE, AND IT IS A CRASH ON CORRECT PYTHON -- 2026-09-15

This ticket's own summary predicted it: *"every construct in this frontend that
hoists has the same escape."* It does, and the third one found is not a stray
side effect -- it **raises and kills the program** on code CPython runs fine.
**That is why this is now prio 80 and no longer 55.** The two rows already here
produce a right answer with a wrong side effect; this one produces no answer at
all.

Found on the lekkerzeilen demo by lekkerzeilen-c8 (menu open, app.py:3130),
reproduced independently here:

```python
class P:
    def pending(self):
        return {"x": 1}

d = {}
staged = d.get("miss")
r = staged.pending() if staged is not None else {}
print("len=%d" % len(r))
```

CPython prints `len=0`. pxx raises
`AttributeError: 'NoneType' object has no attribute 'pending'`, rc=217.

**The trigger is NAME RESOLUTION, which is what makes it look arbitrary:**

| fixture | result |
|---|---|
| no class in the program defines `pending` | correct |
| a class defines some OTHER method | correct |
| a class defines `pending`, same module | **RAISES** |
| a class defines `pending`, imported module | **RAISES** |
| the same code as an `if`/`else` STATEMENT | correct |

A sweep of short-circuit forms whose method name nothing defines comes back
entirely clean -- c8 nearly filed "pxx does not have a short-circuit bug" on
exactly that. **A fixture that does not define the method certifies this bug as
absent**, which is CLAUDE.md's unrepresentative-population trap wearing a new
dress.

## THE MECHANISM, FROM `PXXDBG=a.ast`, AND IT CONFIRMS THE DIAGNOSIS ABOVE

For `r = staged.pending() if staged is not None else {}` the frontend emits, at
STATEMENT level, in this order:

```
1  AN_ASSIGN   __t549 := staged                          hoist the receiver
2  AN_IF       cond NOT(<receiver-is-non-nil>(__t549))
               then AN_CALL(__t549, "pending")            <- the RAISE (nil test)
3  AN_ASSIGN   __t550 := getmem(48)                       <- the else arm's {} literal
4  AN_ASSIGN   r := AN_TERNARY(cond, <the call>, __t550)
```

Steps 2 and 3 sit **outside** the `AN_TERNARY` at step 4. The attribute-missing
guard is hoisted to statement level and runs unconditionally, whichever arm the
ternary would select -- which is this ticket's mechanism exactly, with a raise
instead of a side effect. It also explains the name-resolution trigger: the
guard is only emitted when the attribute name resolves to a known method
somewhere in the compilation, so with no such name there is nothing to hoist and
the row is clean for the wrong reason.

**WHAT THE GUARD EMITS ON AND WHAT IT TESTS ARE TWO DIFFERENT THINGS, and
conflating them mis-states the acceptance test.** It is EMITTED when the
attribute name resolves to a known method somewhere in the compilation (the
table above), and what it TESTS is the receiver for NIL -- the message is just
worded as an attribute failure. Both instruments agree: the fixture where
nothing defines `pending` is clean because no guard is emitted, and on the demo
`panel.more() if isinstance(panel, ui.Menu) else ""` runs for every plain Panel
every frame without raising, because `more` resolves (on `Menu`) but the
receiver is never nil. **So the family crashes iff the receiver CAN be None, not
iff the attribute is missing** -- credit lekkerzeilen-c8, from the demo, against
an earlier reading here that said attribute-presence.

**THE WORST CALL SITE IS NOT THE ONE THIS WAS FOUND ON.** `ui.py:1020`
`Stack.press` does `panel.press(...)` on `panel = self.at(px, py)`, and
`Stack.at` returns None for a click that lands on no panel -- reached unguarded
from `app.py:3298` for any left click that is not on the menu or the icon. If
the hoist fires there, **a left click on open water kills the demo**, which is a
far commoner action than opening the menu. 19 conditional expressions in that
package call a method on an arm whose name resolves; 10 of them guard the very
receiver being called, i.e. the author wrote the guard because it can be None.

**Step 3 answers a question that was open on the demo side: the untaken arm's
`{}` IS allocated, unconditionally, on every evaluation.** That is one wasted
dict per evaluation in a per-frame path. Allocated is NOT the same as leaked --
`__t550` is ARC-eligible and a rebind should release the previous one -- and
nobody has measured whether it leaks. Do not fold it into a leak figure without
that measurement.

## THIS IS THE SAME BUG AS `bug-n-a-hoisted-argument-temp-escapes-a-conditional-that-lives-inside-an-expression`

Same root cause, same fix, different symptom; that ticket carries the better
boundary table (the three CORRECT rows -- `or` short-circuit, dead `for` body,
untaken `if` arm -- which are what say the hoist is statement-local and
working). **Fix once, close both, and check the third row above as the
acceptance test** -- it is the only one of the three that fails loudly, so it is
the cheapest positive control the family has.

## The shape of a fix, not yet chosen

The hoist target is the enclosing statement. A ternary arm is not a statement,
so either the hoisted setup moves into a generated `if` that mirrors the
ternary, or the ternary itself lowers to one. The second is the smaller change
and is what `AN_TERNARY`'s lowering would have to grow; the first duplicates the
condition.

Not attempted here: this was found as a CONSTRAINT on another change, measured,
and banked rather than microfixed.

## What is blocked on it

`PyMakeDynMethCall` runs two paths — direct `pydyn_meth<n>` rungs for four
arguments or fewer, a hoisted `TPyList` past that — and the split exists ONLY
because of this bug. Merge them when it is fixed; the comment there says so.
