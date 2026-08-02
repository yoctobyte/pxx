---
track: N
prio: 70
type: bug
summary: "`self.n += v` where n is an INT field and v an unannotated parameter adds 1, not v. `C(10).add(5)` returns 11. The variant argument is being read as a truthy 1"
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
