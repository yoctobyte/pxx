---
prio: 40
track: N
type: bug
blocked-by: []
status: done
owner: claude-AN
---

# A scalar-then-class rebind INSIDE a nested block loses the widening entirely

- **Type:** bug (NilPy, **silent wrong value**) — **Track N**
- **Found:** 2026-08-09 while gating
  [[bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch]]
- **Pre-existing:** reproduced identically on the PINNED binary, so it is not a
  regression from that fix.

## Measured

```python
class Bare:
    def __init__(self, n):
        self.n = n

if True:
    b = 0
    b = Bare(1)
    print(b + Bare(2))     # CPython: TypeError    pxx: -1094713184
```

At module level the same three lines are correct (`b` widens to a variant and
the addition raises TypeError). Inside a nested block the widening is lost and
the two instance HANDLES are added — a different plausible number every run.

## Narrowed

- `if True:` and `try:` behave the same, so it is **nesting**, not the
  statement kind.
- Remove the `b = 0` and it is correct — so it is the scalar-then-class
  REBIND specifically, not block-scoped binding in general.
- `Bare(1) + Bare(2)` and a module-level `b = 0; b = Bare(1); b + Bare(2)` both
  raise correctly. Only the combination bites.

## Why it matters

Silent and arithmetic: the program computes a plausible integer where CPython
raises. It is also the shape a real file has — bindings inside an `if`, a `try`,
or a loop are ordinary Python, and the module-level form is the artificial one.

## Likely cause (to measure, not assume)

`PyCollectModuleLocalsAST` walks module-level statements and tracks block depth
(`blockIsDef[]`). The suspicion is that a binding inside a non-def block is
harvested differently from a top-level one, so the two bindings of `b` are not
unioned and the LAST one wins as a static class. Confirm with
`PXXDBG=n.locals`: at module level `b` should report `tk=22`, and the nested
form is expected to report `tk=6 rec=<Bare>`.

Note the sibling that WAS fixed: a name bound to two unrelated CLASSES now
widens to a variant ([[bug-nilpy-local-reassigned-across-classes-keeps-one-static-class]],
2026-08-08) — that fix went into the same two harvest loops plus
`PyNoteLocalType`, so those three sites are the place to look, and its `Poly`
flag is the worked example.

## Gate

`.npy` diffed against CPython: the repro above under `if`, `try`, `for` and
`while`; the module-level control that already works; and a case where the
nested rebind is between two SCALARS (int then str), which must keep widening.

## Fixed (2026-08-09, claude-AN)

All four block kinds now match CPython.

### The ticket's own guessed cause was WRONG — this is why it said "measure"

It predicted `tk=6 rec=<Bare>` (the last binding winning as a static class).
`PXXDBG=n.locals` says **`b tk=13 rec=-1`** — tyInt64. The nested
`b = Bare(1)` binding was not harvested *at all*; `b` simply kept the type of
the module-level `b = 0`. So it is not a union that picks wrong, it is a
binding that never reaches the union.

### Cause

`PyCollectModuleLocalsAST`'s depth>0 arm deliberately recognises only a few
RHS *shapes* — a literal, a bracket/brace display, int arithmetic, a bare name —
because trial-parsing an arbitrary RHS inside a block can `Error()` and halt the
whole compile on a name the pre-pass cannot yet see. That guard is right and is
left intact. A **constructor call of an already-declared class** simply belongs
in the safe list: recognising `Cls(` needs no parse, only that the identifier
resolves through `FindUClass` and is followed by `(`.

Noting it as `tyClass` is all that is required — `PyWiden(tyInt64, tyClass)`
yields a variant, the honest answer for a name holding both, and the runtime
dunder dispatch landed earlier tonight
([[bug-nilpy-module-global-rebound-scalar-then-class-loses-dispatch]]) then
handles the operand correctly. Without that companion fix this one would have
turned a wrong number into a *different* wrong behaviour rather than into
CPython's answer.

### Verification

`test/test_nilpy_block_nested_rebind_widens.{npy,expected}` (`.expected` from
CPython): the repro under `if`, `try`, `for` **and** `while` — they share the
depth tracking but are separate statement shapes, and the original repro was
found under `try` and only later shown to be nesting rather than exceptions —
plus a nested rebind to a class that DOES define `__add__` (must dispatch, not
raise), the module-level control, a nested scalar-to-scalar rebind that must
still widen and must NOT be captured by the new arm, and a nested binding with
no prior scalar that must still be usable as its class.

Every case CATCHES the TypeError rather than comparing tracebacks: the uncaught
message wording differs from CPython's, and pinning that text would freeze an
unrelated detail.

`gate.sh quick` GREEN. `test_nilpy_{rebind_type,rebind_across_unrelated_classes,
with_name_reuse,class_field_identity}` and ten session probes re-diffed against
CPython: unchanged.

## Log
- 2026-08-09 — resolved, commit 5d9d64e1b.
