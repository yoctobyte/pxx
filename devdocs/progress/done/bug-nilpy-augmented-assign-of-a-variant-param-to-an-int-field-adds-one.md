---
track: N
prio: 70
type: bug
summary: "`self.n += v` where n is an INT field and v an unannotated parameter adds 1, not v. `C(10).add(5)` returns 11. The variant argument is being read as a truthy 1"
status: done
---

# `self.n += v` adds 1 instead of v when v is a variant parameter

- **Type:** bug (NilPy — SILENT WRONG VALUE) — **Track N**
- **Found:** 2026-08-02, while gating
  [[bug-nilpy-augmented-assign-to-a-variant-typed-field-corrupts-it]].
  **Pre-existing** — confirmed against a stashed baseline build, so it is not
  fallout from that fix, which is about the opposite typing (variant FIELD,
  literal operand).

## Repro

```python
class C:
    def __init__(self, n: int):     # ANNOTATED — the field is a real int
        self.n = n
    def add(self, v):               # UNANNOTATED — v is a variant
        self.n += v
        return self.n

print(C(10).add(5))                 # CPython 15    pxx 11
```

10 + 1 = 11. The variant `v` contributes **1** regardless of its value, which is
what a truthiness test yields for any non-zero — so the variant argument is
almost certainly being read as a Boolean rather than unboxed to its number.

## Note the typing, because it is the mirror image of the sibling ticket

| field | operand | result |
| --- | --- | --- |
| variant (unannotated ctor param) | literal `3` | fixed by the sibling ticket |
| **int (annotated ctor param)** | **variant (unannotated method param)** | **this ticket: adds 1** |

So the two tickets are the two sides of the same missing conversion, and fixing
one does not fix the other — measured, not assumed. The sibling's fix routes the
statement through the variant-aware binop when the LVALUE is variant; here the
lvalue is a plain int and it is the RHS that needs unboxing.

## Where to look

The int-typed augmented path with a variant right-hand side. `self.n = self.n +
v` (the explicit spelling) is worth measuring first — if that is correct, the
difference is again the augmented lowering and not the binop, which would make
this a close cousin of the sibling fix rather than a new area.

## Gate

A `.npy` diffed against CPython: `+=`, `-=`, `*=` on an annotated int field with
an unannotated parameter operand; the same with an annotated parameter (control);
the explicit `self.n = self.n + v` spelling; the same shapes on a plain local
with a variant operand; and a str field with a variant operand.

## Log
- 2026-08-02 — resolved, commit dfb3d37a9.

## Resolved 2026-08-02

The ticket's own "where to look" was right on both counts: the explicit
`self.n = self.n + v` spelling IS correct, so the difference is the augmented
lowering rather than the binop — which made this a close cousin of the sibling
fix, exactly as predicted.

Same compound-assignment tail. The sibling routed a NilPy VARIANT LVALUE to the
explicit form; this widens that condition to **either side** being a variant, and
the same rewrite carries it.

### The typing was the trap, and it cost a wrong first attempt

Taking the rewritten binop's type from the LVALUE (an int field stays an int,
which sounds right) makes an int-typed binop over a 16-byte variant slot: every
result came back a pointer — `140733931812968` for each of the five values on the
first line. Widening the two operand types is what the written-out spelling gets,
and that spelling is the measured-correct reference. Recorded because the wrong
version is the intuitive one.

`test/test_nilpy_augmented_assign_variant_operand.npy` (+ `.expected`, wired into
`make test-nilpy`) is byte-identical to CPython across `+=`, `-=`, `*=` with a
variant operand, the annotated control, a str field, a both-variant case, plain
locals, the explicit spelling, and accumulation across calls.

Also re-verified after the change: the realistic bank-account program this whole
thread was reduced from, the dict-subscript method-call probe, the variant-field
augmented tests and the floor-division tests — all agree with CPython.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.
