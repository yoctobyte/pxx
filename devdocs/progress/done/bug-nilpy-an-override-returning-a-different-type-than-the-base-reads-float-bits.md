---
track: N
prio: 58
type: bug
blocked-by: []
summary: "An overriding method whose return type differs from the base's is stored into the BASE's return slot with no conversion: base `return 0` + override `return 1.5` prints 4609434218613702656 — the IEEE bits of 1.5 read as an integer — and arithmetic on it silently continues. The mirror direction (int override of a float base) either renders 6 as 6.0 or fails to compile with 'invalid IR node reference in store_sym'"
status: done
owner: claude-AN
---

# An override returning a different type than the base reads float BITS as an int

- **Type:** bug (silent wrong value) — **Track N** (NilPy method return-type
  unification; the store itself is IR, so the fix may reach into Track A ground —
  file separately if it does)
- **Found:** 2026-08-12, differential bug hunting against CPython.
- **Twelve lines, no exotic features.** Ordinary single inheritance with an
  override — the first thing anyone writes after `class`.

## The repro

```python
class A:
    def v(self):
        return 0

class B(A):
    def v(self):
        return 1.5

xs = [A(), B()]
for x in xs:
    print(x.v())
b = B()
print(b.v())
print(b.v() + 1)
```

| | pxx | CPython |
| --- | --- | --- |
| `A().v()` | `0` | `0` |
| `B().v()` through the list | **`4609434218613702656`** | `1.5` |
| `b.v()` on the static type | **`4609434218613702656`** | `1.5` |
| `b.v() + 1` | **`4609434218613702657`** | `2.5` |

`4609434218613702656` is `1.5`'s IEEE-754 bit pattern read as an integer, and
the `+ 1` shows the wrongness propagating through arithmetic rather than
stopping at the print. Nothing is raised or warned.

## The full matrix — the direction decides which of THREE failures you get

| base returns | override returns | pxx |
| --- | --- | --- |
| `0` (int) | `1.5` (float literal) | **bit pattern**, silent |
| `0` (int) | `1.5 * 2` (float expr) | **bit pattern**, silent |
| `0.0` (float) | `6` (int literal) | `6.0` where CPython says `6` |
| `0.0` (float) | `2 * 3` (int expr) | **compile error**: `invalid IR node reference in store_sym` |
| `0.0` (float) | `2 + 3` | same compile error |
| `0.0` (float) | `x = 2 * 3; return x` | same compile error |
| `0.0` (float) | `self.w * self.h` | same compile error |
| no base at all (`class B:` alone) | `2 * 3` | correct — `6` |

So the override's own inferred type is right and the LITERAL cases are handled
(one by conversion, one by reinterpretation); it is specifically an override
being fitted to the base's slot. A bare int literal converts, a computed int
expression cannot even be emitted, and a float never converts at all.

## Why it matters

Different return types across an override is not an edge case in Python —
`area()` returning `0.0` in an abstract base and `w * h` in a subclass is the
textbook example, and that exact shape is a compile error today. The int-into-
float direction is the loud one; the float-into-int direction is silent, and a
number in the 4.6e18 range is exactly the kind of value that reads as a hash or
an id rather than as corruption.

## Where to look

`PyMethodRetType` decides the signature and the header pass decides the frame —
the pair whose disagreement the code already calls "a silent ABI mismatch". For
an override, the inherited method's row is what the caller binds against, so
either

1. the override's result must be CONVERTED into the base's declared type (right
   for the int-literal row that already works, but it is not what CPython does —
   `B().v()` really is an int there), or
2. a method whose overrides disagree about the return type must be widened to
   **tyVariant** across the whole chain, which is what NilPy already does for a
   name bound to unrelated classes (`PyNoteLocalType`'s `Poly` flag) and is the
   only option that reproduces CPython for both directions.

(2) is almost certainly the answer, and it also explains the compile error: the
non-literal int expression has no conversion path into the float slot at all, so
nothing valid can be emitted today.

## Gate

A `.npy` diffed against CPython covering every row of the matrix above:
both directions, literal and computed, dispatch through a base-typed container
AND on the static subclass type, plus arithmetic on the result so a bit pattern
cannot pass as a plausible number.

## Log
- 2026-08-12 — resolved, commit PENDING-COMMIT.
