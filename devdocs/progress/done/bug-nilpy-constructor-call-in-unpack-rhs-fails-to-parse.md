---
track: N
prio: 55
type: bug
status: done
---

# A constructor call in an unpacking right-hand side won't parse

- **Type:** bug (NilPy frontend gap — loud) — **Track N**
- **Found:** 2026-08-02, by a differential sweep against the CPython oracle.

## Measured

```python
class A:
    def w(self):
        return "A"

a, b = A(), A()      # error: unexpected token
```

The boundary is sharp, and it is not about arity or about calls in general:

| form | result |
| --- | --- |
| `a = A()` — single assignment | ok |
| `a, b = f(), f()` — FUNCTION calls | ok |
| `a, b, c = f(), f(), f()` | ok |
| `a, b, c = 1, 2, 3` | ok |
| `a, b, c = [1, 2, 3]` | ok |
| `xs = [A(), A()]` then `a, b = xs` | ok |
| **`a, b = A(), A()`** | **unexpected token** |
| **`a, b = A(), 1`** | **unexpected token** |
| **`a, b = 1, A()`** | **unexpected token** |

So: a CONSTRUCTOR call anywhere in an unpacking right-hand side, in any
position, kills the parse — while the same constructor is fine in a single
assignment and fine inside a list literal that is then unpacked.

## Likely cause

Ordinary calls work, so the unpack RHS parser handles calls in general. What is
different about `A()` is that `A` is a CLASS NAME — in the single-assignment
path that is routed to construction, but in the unpack RHS list the name is
presumably taken as a TYPE (a typecast or class reference) and the `(` then
does not fit. `PyIsBuiltinConvName` / the `IsClassType(name)` test in
`pyparser.inc` around the conversion-builtin handling is the neighbourhood to
look at.

Worth confirming by dumping tokens before theorising — the repo's own note is
that a wrong root cause here is easy to reach
(`project_dump_tokens_before_theorising`).

## Why it matters

`a, b = Foo(), Bar()` is ordinary setup code, and the failure is a bare
"unexpected token" that points at the line without saying what is wrong — so it
reads as a syntax error in the user's code rather than a missing feature.

## Gate

A `.npy` diffed against CPython covering a constructor in every RHS position
(first, last, middle, alone), mixed with literals and function calls, a
subclass constructor, and a constructor with arguments — plus the single
assignment and list-then-unpack forms as controls.

## 2026-08-02 — this is TYPE ERASURE, and it has a SILENT half the title hides

Re-measured at HEAD by a differential sweep. The parse error is real and still
reproduces with non-colliding names (`p, q = Thing(), Thing()` then `p.w()`), so
it is not the case-insensitivity bug that was fixed the same day. But framing
this as "won't parse" points the fix at the parser, and the parser is not where
the problem is.

**Unpacking erases the class identity of its targets.** The target becomes a
variant, and everything downstream follows from that:

- a **method call** on the target does not resolve — the loud half, which is
  what this ticket recorded
- a **dunder** on the target does not dispatch — the SILENT half, which nobody
  had measured

```python
class Counter:
    def __init__(self, n):     self.n = n
    def __len__(self):         return self.n
    def __eq__(self, o):       return self.n == o.n
    def __str__(self):         return "C(" + str(self.n) + ")"
    def __contains__(self, v): return v == self.n

a, b = Counter(3), Counter(3)
print(len(a), a == b, str(a), 3 in a)
# CPython: 3 True C(3) True
# pxx    : 1 False 123581388292120 <segfault on `3 in a`>
```

`str(a)` printing a POINTER and `a == b` answering False are exactly the failure
shapes this repo treats as worst-case: confident, well-formed, wrong.

### The control that names the cause

```python
a = Counter(3)
b = Counter(3)
print(len(a), a == b, str(a), 3 in a, 4 in a)   # byte-identical to CPython
```

Two separate assignments — same classes, same calls, same dunders — are entirely
correct. Only the unpacking form loses it.

### Why this is NOT simply the runtime-dunder cluster

It looks like [[feature-nilpy-runtime-dunder-dispatch-on-variants]], which lists
"unpacking from a container" among its entry points, and if the RHS were an
arbitrary iterable it would be — the class genuinely is unknown then, and that
needs the Track U decision.

But here the RHS is a **tuple DISPLAY of constructions whose classes are known at
compile time**. `a, b = Counter(3), Counter(3)` has nothing erased about it
except by pxx's own lowering. Typing each unpack target from the corresponding
RHS element, when the RHS is a literal tuple, needs no runtime dispatch and no
decision — and it fixes both halves at once, the parse error included.

That makes this ticket **separable from the blocked cluster**, which is the main
reason for writing this down: it currently reads like a small parser gap, and it
is actually a self-contained type-propagation fix with a silent wrong-value half.

### Gate (revised)

The existing table, plus: a method call on each unpacked target; `__len__`,
`__eq__`, `__str__`, `__contains__` on an unpacked target, diffed against
CPython; the two-separate-assignments control; and an unpacking whose RHS is a
genuine iterable (a list, a function return) left behaving as it does today,
since that one really does belong to the runtime-dispatch cluster.

## Resolved 2026-08-02 — commit 3ccb6576d

One omission, in `PyUnpackTargetStore`: the target got the temp's type KIND but
not its `RecName`. Both halves above follow from that, and both are fixed by
carrying the identity through.

Conservative on rebinding — a name that already carries a class identity is left
alone, because a name holding two different classes over its life is the widening
case the module/local tables own, not something the unpack path should decide.

`test/test_nilpy_unpack_keeps_class_identity.npy` (+ `.expected`, wired into
`make test-nilpy`) is byte-identical to CPython and carries both halves, the
separate-assignment control that named the cause, mixed target lists
(`r, s = Thing(), 5` and its mirror), and the shapes that already worked.

`gate.sh quick` GREEN, self-host fixedpoint byte-identical.

### Found alongside, NOT fixed

`m, n = "xy"` — unpacking a STRING into several names — is refused with "cannot
unpack this value into several names — it is not a list, tuple or variant".
CPython unpacks any iterable, strings included. Loud rather than silent, and
unrelated to the identity bug; worth its own ticket if a corpus wants it.

## Log
- 2026-08-02 — resolved, commit 3ccb6576d.
