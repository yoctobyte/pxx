---
slug: bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed
title: arithmetic on a user class fails when the other operand is object-typed
summary: >
  `v * k` where `v` is a user class defining `__mul__` and `k` is a value the
  compiler types as `object` raises `TypeError: expected a number, got object`
  instead of dispatching to `__mul__`. A value becomes object-typed the ordinary
  way: an attribute assigned from a PARAMETER (`def __init__(self, k): self.k = k`)
  rather than from a literal. All four arithmetic operators are affected
  (`+ - * /`), int and float alike. The identical body reached through a NAMED
  method (`v.scale(k)`) is correct, so this is the operator's dynamic dispatch and
  not the arithmetic. It is loud, which is the one good thing about it.
track: N
type: bug
prio: 65
owner: unassigned
status: open
---

## How it was reached

lekkerzeilen `--open-water` under `setarch -R`, after the adjacent-literal
splice at app.py:4033 is parenthesised out of the way (see
`bug-n-adjacent-string-literals-splice-a-plus-so-a-tighter-operator-binds-wrong`).
The run then gets into the frame loop -- the first time this demo has -- and
dies on frame 1 at:

```
app.py:4156   self.camera.update(self.boat.view, frame, self.env)
 -> app.py:439  desired_eye = (state.position + behind * self.distance
                               + Vec3(0.0, self.height, 0.0))
```

`behind` is a `Vec3` with `__mul__`; `self.distance` is set in
`Camera.__init__(self, distance=11.0, height=1.5)` as `self.distance = distance`.
Because the value arrives through a parameter it is object-typed, and the `*`
never reaches `Vec3.__mul__`.

Located by statement-level trace, then confirmed with a raise probe: a probe
placed before app.py:4156 fires, a probe placed before app.py:4157 does not.

## Repro

One file, no imports. Every row should print a `V3`.

```python
class V3:
    def __init__(self, x=0.0):
        self.x = x

    def __add__(self, o):
        return V3(self.x + o)

    def __mul__(self, s):
        return V3(self.x * s)

    def scale(self, s):
        return V3(self.x * s)

    def __repr__(self):
        return "V3(%.2f)" % self.x


class Par:                       # k arrives through a PARAMETER
    def __init__(self, k=11.0):
        self.k = k


class Lit:                       # k is a literal
    def __init__(self):
        self.k = 11.0


v = V3(2.0)
print("v * Lit().k  ->", v * Lit().k)     # V3(22.00) -- correct
print("v.scale(Par().k) ->", v.scale(Par().k))   # V3(22.00) -- correct
print("v * Par().k  ->", v * Par().k)     # TypeError: expected a number, got object
```

## The table

`par.k` is `11.0` assigned from a parameter; `v` is `V3(22.0)`.

| row | CPython | pxx @ 744d673cf |
| --- | --- | --- |
| `v + par.k`  (`__add__`) | `V3(33.00)` | **TypeError** |
| `v - par.k`  (`__sub__`) | `V3(11.00)` | **TypeError** |
| `v * par.k`  (`__mul__`) | `V3(242.00)` | **TypeError** |
| `v / par.k`  (`__truediv__`) | `V3(2.00)` | **TypeError** |
| `v * par.n`  (int attribute) | `V3(66.00)` | **TypeError** |
| `v * req.k`  (no default in the signature) | `V3(11.00)` | **TypeError** |
| `loc = par.k` first, then `v * loc` | `V3(11.00)` | **TypeError** |
| `v * (par.k + 0.0)` | `V3(11.00)` | **TypeError** |
| `freemul(v, par.k)`, i.e. `a * s` in a free function | `V3(11.00)` | **TypeError** |
| `v.scale(par.k)` -- same body, named method | `V3(11.00)` | `V3(11.00)` |
| `v * float(par.k)` | `V3(11.00)` | `V3(11.00)` |
| `v * 11.0` -- literal | `V3(11.00)` | `V3(11.00)` |
| `freemul(2.0, par.k)`, i.e. `2.0 * s` | `22.0` | `22.0` |
| `v * lit.k` -- attribute from a LITERAL | `V3(11.00)` | `V3(11.00)` |

Measured at 744d673cf, compiler binary 2026-09-14 03:42, x86-64 `--threadsafe`.

Four readings out of that:

1. **It is the operator, not the arithmetic.** `v.scale(par.k)` and
   `v * par.k` have byte-identical bodies (`V3(self.x * s)`) and only the
   operator form fails. Whatever the `*` lowering does when it cannot type the
   right operand statically, it is not "call `__mul__`".
2. **Defaults are irrelevant.** `Req.__init__(self, k)` with no default fails
   the same way. The condition is "assigned from a parameter", not "assigned
   from a defaulted parameter" -- this is NOT
   `bug-nilpy-a-defaulted-argument-is-dropped-when-the-first-argument-iterates`
   (aa43f495a) wearing a different hat.
3. **Retyping through arithmetic does not help, `float()` does.**
   `par.k + 0.0` stays object; `float(par.k)` does not. That says the object
   taint is on the value's declared type and propagates through binary ops, and
   that a conversion call is the only thing that currently re-narrows it.
4. **`2.0 * par.k` is fine.** A builtin-numeric left operand unboxes an object
   right operand correctly. Only a USER CLASS on the left goes down the path
   that raises -- which is exactly the path that would have had to consult
   `__mul__`.

## Where to look

The message text `expected a number, got object` is the hook. The suspicion is
that the binary-operator lowering picks its arm from the STATIC type of the
operands, finds a user class on the left and a `tyObject` on the right, and
falls through to the numeric coercion helper instead of the dunder-dispatch
helper -- because the dunder arm is only entered when both sides are known. The
fix is presumably to make an object-typed operand force the dynamic arm rather
than the numeric one, since dynamic dispatch is correct for both cases and the
numeric one is correct for only one.

Worth checking in the same place: `%`, `**`, `//`, `<<`, and the augmented forms
(`v *= par.k`), none of which I measured; and comparison dunders
(`__eq__`, `__lt__`) against an object-typed operand, which would fail silently
rather than loudly if they share the lowering.

## What it costs the demo

This is the entire `--open-water` wall at 744d673cf. `Camera.__init__`
taking `distance` and `height` as parameters is not an unusual thing to write --
it is what you write so a caller can pass a different camera -- and every read
of `self.distance` in `Camera` is poisoned by it. Three of `Camera`'s five
methods do arithmetic on it.

## Gate

`make test-nilpy` + self-host byte-identical, plus a `.npy` carrying the table
above with expectations taken from CPython. Include the four passing rows as
well as the failing ones: `v.scale(par.k)` is the control that says this is the
operator lowering, and `v * lit.k` is the control that says it is the operand's
type and not the class.

## Log
- 2026-09-14 -- filed from the lekkerzeilen `--open-water` frame loop, reached
  for the first time. Reduction is single-file and inline above.

## Provenance

Measured and written by the peer session **lekkerzeilen-c8**, which cannot
commit in this checkout; this file is left untracked for that seat to pick up.
Found by parenthesising the known splice at app.py:4033 in a SCRATCHPAD copy of
the demo (the owner's tree is untouched) to see what lay behind it, then
statement-tracing the frame loop. The ablation that produced the precondition is
recorded above as the `Lit` / `Par` contrast: the same class with the same
attribute value fails or passes depending only on whether the value came from a
literal or a parameter.
