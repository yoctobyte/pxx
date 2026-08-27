---
track: N
prio: 58
type: bug
owner: frank1-AN
blocked-by: []
summary: "`self.w = None` in the ctor, `self.w = Foo()` later, then `self.w.hi()` returns an INTEGER — the receiver's address — instead of calling the method. The idiomatic `self.w: Optional[Foo] = None` spelling is wrong the same way, which is what makes it expensive."
status: done
---

# A method call on an Optional class field returns a raw pointer

- **Type:** bug (Track N) — **silent wrong value**, no diagnostic anywhere.
- **Found:** 2026-08-27, while probing the cross-hierarchy field join for
  [[bug-n-a-field-declared-in-an-ancestor-is-not-widened-by-a-descendants-rebind]].
  It is NOT caused by that work: it reproduces identically on pinned **v388**
  (`e8b72f8afeb6`) and on HEAD, and it needs no inheritance at all.

## Repro

```python
class Foo:
    def hi(self):
        return "foo"

class A:
    def __init__(self):
        self.w = None
    def go(self):
        self.w = Foo()
        return self.w.hi()

print(A().go())
```

| | |
| --- | --- |
| CPython | `foo` |
| pxx (v388 and HEAD alike) | `184` — an address, printed as an integer |

## The annotated form is wrong too, and that is the expensive half

```python
from typing import Optional
class A:
    def __init__(self):
        self.w: Optional[Foo] = None
    ...
```

prints `176`. This is the form the frontend's own comments call idiomatic (the
one the uforth VM uses), and it is the form a user reaches for precisely
*because* they were told the annotation carries the type. It does not help here.

## Shape of the defect

The field is declared by `self.w = None`, so its type is decided by whatever
`None` infers to, and the later `self.w = Foo()` does not change the ANSWER at
the call: `self.w.hi()` neither dispatches nor errors — it yields the receiver
itself. So the failure is not "the field is the wrong width" (the value stored
IS the instance) but "an attribute selector on a field of this type degrades to
the bare receiver", which is the same silent degradation shape as
[[bug-n-an-attribute-on-an-unresolved-import-degrades-to-a-bare-name]].

Not investigated further; the diagnosis above is where the probe stopped.
Whoever takes it should start by printing the field's recorded type
(`PXXDBG=n.locals` / the field tables) for both spellings rather than reasoning
about what `None` infers to — measure, do not reason.

## Gate

Both repros above print `foo`, plus a control that a field left `None` and
never assigned still reads as None, and one that `if self.w is not None:`
still narrows the way it does today.

---

## 2026-08-27 — RESOLVED. My own filing was wrong about the cause: `None` is irrelevant.

I filed this yesterday-shaped diagnosis — "a field that was `None` at
declaration" — from one observation, which is the mistake this repo keeps
paying for. Varying the shape took it apart in four measurements.

### The boundary

```
class Foo:
    def hi(self):  return "foo"
    def num(self): return 42
```

| written | result |
| --- | --- |
| `self.w = Foo()` — no `None` anywhere — then `self.w.hi()` | **also broken** (176) |
| `print(self.w.hi())` inline | correct — `foo` |
| `s = self.w.hi(); return s` | **176** |
| `n = self.w.num(); return n` | correct — `42` |

So it is not `None`, not the field, and not the call: it is **a local assigned
from a method call, and then returned**. And `PXXDBG` said which half was wrong,
in one line each:

```
n.locals  A.viaField  s tk=23        <- tyAnsiString. The locals table was RIGHT.
n.ret     A.viaField    tk=8         <- tyUInt8. The def's return type was WRONG.
```

Two spellings of one question and the second is the broken one, which is what
`devdocs/dev/normalise-dont-special-case.md` is about.

### The cause, found by bisecting the SOURCE rather than the compiler

`f.zqx()` typed fine; `f.hi()` did not. The trigger is the **method's name**.

`PyInferExprType`'s call arm takes any `name(` as a free routine and asks
`FindProc`. For `hi` that finds **Pascal's `Hi`** — the high-BYTE intrinsic —
case-insensitively, and types the whole expression `tyUInt8`. The def then
declares a Byte result and hands back a string handle. `Foo().me().hi()`
segfaulted; `Foo().hi()` printed 176; nothing warned.

This is the **fourth site** of one family — Pascal's case-insensitive lookup
answering for a case-sensitive Python name, after `PyIsClassTypeExact`,
`PyIsExactCtorName` and the MEMBER arm's `FindUClass` guard.

### Why the obvious fix is wrong, and what separates the cases

"A name after a dot is a member, not a free call" would also break
`math.sqrt(2.0)` — a module-qualified call IS a flat lookup here, and it reaches
Pascal's **capitalised** `Sqrt`, so an exact-case rule fails too. What separates
`f.hi()` from `math.sqrt()` is not the spelling but the **receiver**: a local or
parameter has members, a module name does not.

`PyDottedRootIsLocal` walks back to the ROOT of the dotted chain (`self` in
`self.w.hi()`) and asks `PyNameBoundInDef` — the routine that already exists to
tell a name that merely SPELLS a class from one that denotes it. When the root
is bound in this def, the flat lookup is skipped and the expression falls
through to this scan's `tyVariant`, which is the honest "cannot type it here"
and exactly what an unrecognised method name already got.

It needs the def's token ranges, which `PyInferExprType` has no parameter for
and is called from ~50 places. So the scan publishes them in globals — the same
shape `PyInferSelfCi` uses and for the same reason — initialised to **-1, not
the BSS zero**, because 0 is a valid token index and an unset range would read
as "the def starting at token 0". `PyInferDefRetTypeScan` is now a save/restore
wrapper around the scan proper, because it re-enters itself for a nested def and
the inner range must not outlive it.

### A second, independent defect found on the way

`u = Foo().hi()` was typed **tyClass Foo** — the construction arms answered with
the class and simply ignored every selector after the ctor's `)`. `Foo().tag`
and `Foo().me().hi()` are the same shape. `PyCtorSelectorType` now walks the
selector chain through the class tables (`FindUMeth` → `Procs[].RetType`,
`FindUField` → `UFldTk`), and returning `tyUnknown` for a chain it cannot follow
makes the caller fall through to the general walk rather than claim the class —
claiming the class is the bug, not the fallback.

### Measured

- Self-host fixedpoint `ecf52e008b11`, converged in 1 round.
- 13 probe programs, every one now byte-identical to CPython, including the
  three controls that had to keep working: `math.sqrt`, `json.dumps`, and a str
  method on a literal.
- `test_nilpy_method_call_result_assigned_to_a_local` — 10 rows, all matching
  CPython: field / local / direct / chained / attribute receivers, an
  int-returning method that was never broken, a module-level def, and the three
  controls. **v388 pinned prints `240`, `72`, and then stops.**
- A targeted differential over the NilPy tests naming return / infer / def /
  method / str / call / type / local / nested / lambda / closure / property /
  field / class, new binary vs the field-join binary `2df38cd9b`.

### Left open

The ticket's Gate asked for a control that `if self.w is not None:` still
narrows as it does today. That is unaffected by this change — nothing here
touches narrowing — and is not covered by the new test.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
