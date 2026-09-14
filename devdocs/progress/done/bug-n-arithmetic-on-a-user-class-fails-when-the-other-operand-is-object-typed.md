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
status: done
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

## The full operator matrix (2026-09-14, measured at c53d9ab55)

Object-typed right operand, user class on the left, every dunder defined:

| operator group | result |
| --- | --- |
| `+  -  *  /  //  %` | **TypeError** |
| `<  <=  >  >=` | **TypeError** |
| `**` | correct |
| `<<  &  \|  ^` | correct |
| `==  !=` | correct |
| `v[k]`, `k in v` | correct |
| `v *= k`, `v += k` and the other augmented forms | correct |

So it is not "all arithmetic": it is exactly the operators with a builtin
numeric fast path, **minus `**`**, plus the four orderings. Two entries from
this ticket's own "worth checking" list are hereby answered and can be struck:
the augmented forms are fine, and the comparison dunders fail LOUDLY rather than
silently. `%` being in the broken set is the one to keep — it is also the
string-format operator, so anything defining `__mod__` is exposed.

## Mechanism, read out of the compiler source

Three different causes wearing one error message. None of this required a build.

**1. `+` and `-` — the variant arm runs first.** In `ParseSimpleExpr`
(`compiler/pasparser_expr.inc`) the variant arm is at **11163**:

```pascal
else if (ASTTk[left] = Ord(tyVariant)) or (ASTTk[right] = Ord(tyVariant)) then
  ASTTk[node] := Ord(tyVariant)
```

and the user-class `__add__`/`__sub__` arm is at **11254**, ninety-one lines
further down the same `else if` chain. A variant on EITHER side claims the node
before the dunder arm is ever tested, so `v + par.k` is tagged arithmetic and
the class handle is coerced to a number.

**2. `*  /  //  %` — the same shape, one chain over.** Variant arm at ~**10727**,
user-class `__mul__`/`__truediv__`/`__floordiv__`/`__mod__` arm at ~**10747**.

The fix precedent is already in this file, forty lines above the first one, and
its comment states the general rule for exactly this situation
(`bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic`):

> BEFORE the variant arm below, not after. A repeat is decided by the SEQUENCE
> operand, which is statically known here [...] while the COUNT may be anything,
> including a variant. Sitting after the variant arm, the whole pair was tagged
> tyVariant the moment the count had no static type and the repeat builders were
> never reached.

Word for word this bug. The list-repeat and bytes-repeat arms were moved above
the variant arm for that ticket; the user-class dunder arms were left below it.
They are decided by the LEFT operand, which is statically known, so the same
argument applies unchanged.

**3. The four orderings — an over-broad guard, not an ordering problem.** The
ordering arm at **11939** excludes a variant on EITHER side:

```pascal
if PyExprMode and (op in [tkLt, tkLe, tkGt, tkGe]) and
   (IntToTypeKind(ASTTk[left]) <> tyVariant) and
   (IntToTypeKind(ASTTk[right]) <> tyVariant) and ...
```

That guard came from `833f3ccba`, repairing
`regression-test-nilpy-test-nilpy-variant-operand-arith-dunders`: `2e2c5b939`
had widened the arm to "EITHER operand is a user class", which swept in variant
pairs, and the arm has **no fall-through** — finding no dunder it emits
`PyNotOrderableError`, turning a case pylib's `pycmp_v` used to answer correctly
at run time into a compile-time refusal.

The right-hand exclusion is collateral damage from that repair. Its stated
reason justifies only the LEFT one:

> Python asks the LEFT operand's type first, and with the left a variant we
> cannot know whether it has the direct dunder [...] Both directions are
> therefore excluded, not just variant-on-the-left.

With the left a statically-known user class, `left.__lt__(right)` IS what Python
does, whatever the right turns out to be. The narrowest safe widening is to
admit `right = tyVariant` only when `ordLCi >= 0` and
`FindUMeth(ordLCi, ordDirect) >= 0` — i.e. only when the arm can dispatch
without needing the fall-through it does not have. Every case that would have to
refuse still stays out, so `833f3ccba` is preserved exactly.

**Why `**` escapes.** It is not a binop token at all. `compiler/pyparser.inc`
~31884: "`**` is not a binop TOKEN — it lowers through pypow_v (and the
`__pow__`/`__rpow__` dunders), so this cannot go through the AN_BINOP path
below". It never meets the variant arm, which is the whole reason it is the odd
row out.

**Why `<<  &  |  ^  ==  !=`, subscript and `in` escape.** They reach the runtime,
where `PyVarUserObj` (`compiler/builtin/pylib.pas` ~6406) asks the one-sided
question — "ONE side being a user object is what actually licenses a dunder
call" — which is the correct predicate and is applied there and not here.

## The existing regression test covers the other half

`test/test_nilpy_variant_operand_arith_dunders.npy` opens with

```python
lhs = 0        # forces `lhs` to a VARIANT, which is what kills static dispatch
```

— variant on the **LEFT**, user class on the right. That is the mirror of this
ticket, which is variant on the RIGHT and a statically-known user class on the
left. The file's own note says "an unannotated parameter or an element pulled
out of a list is another" way to get a variant operand; `self.k = k` in an
`__init__` is a third, and none of the three is exercised on the right-hand
side. Adding the right-hand rows to THAT file rather than a new one keeps the
pair together.

## What it costs the demo, updated 2026-09-14

This is now the ONLY wall on every entry point. After `92b0e3a71` the six world
rows moved 139 -> 217 and land on the adjacent-literal splice at app.py:4033;
with that one line parenthesised in a scratch copy, every path -- world and
`--open-water` alike -- arrives here, at `Camera._chase` app.py:439, because
`Camera.__init__(self, distance=11.0, height=1.5)` does `self.distance = distance`.
`--shot` reaches it without needing the splice parenthesised at all.

## Resolution — the cause is one layer below the parser (2026-09-14)

Fixed in `compiler/builtin/pylib.pas`, not in the parser. The arm-order
asymmetry diagnosed above is real and is NOT what was biting: the class handle
DID reach the runtime correctly boxed as an object variant (tag 7), and the
runtime is where it was refused.

**One predicate, eight copies, all requiring two objects.** Each of the eight
variant arithmetic entry points — `pyadd_v`, `pysub_v`, `pymul_v`,
`pytruediv_v`, `pyfloordiv_v`, `pyfloormod_v`, `pymod_v`, `pypow_v` — carried
its own copy of the guard before attempting a dunder:

```pascal
if (PPyVarRec(@a)^.VType = 7) and (PPyVarRec(@b)^.VType = 7) and ...
```

BOTH sides must be objects. That is the identical drift `PyVarUserObj` was
written to end for the four COMPARISON entry points, recurring one family over,
and that function's own comment already states the predicate this family needed:

> One side being a user object is what actually licenses a dunder call, and
> requiring two is what made `2 in [M(2)]` False and `g < 9` die with "expected
> a number, got object" on a class that declares `__lt__`. Four copies of a
> predicate is how they drifted, so there is now one.

Four became one for comparisons; eight stayed eight for arithmetic. The fix is
one new helper, `PyVarUserArith`, asking the one-sided question once — each of
the eight four-line guards is now a single line.

**The row that says the parser fix alone would not have been enough:**

```python
ww = 0
ww = W(3.0)
ww * 2.0        # variant HOLDING the object, plain float literal
```

Neither side has a static class, so no compile-time dispatch can reach it, and
it was broken exactly like the rest. It is in the fixture.

### The orderings — half retracted, and the other half is a separate bug

The matrix row above reads `< <= > >=` as broken. It is right about the
observable and wrong about the condition, and the condition is the dunder's
RETURN TYPE, not the operand's:

| `__lt__` returns | against a variant operand | pxx @ 80840e14f |
| --- | --- | --- |
| `True` (a bool) | `v < par.k` | correct |
| `7`, `1.5`, `"LT"`, `[1]`, `None` | `v < par.k` | **TypeError** |
| `"LT"` | `v < 11.0` (a LITERAL operand) | correct |
| `"EQ"` from `__eq__` | `v == par.k` | correct |

So with a bool-returning ordering dunder — which is what the operator means and
what real code writes — the four orderings were already correct BEFORE any
change here, and `833f3ccba`'s variant exclusion needs no widening: the pair
falls through to `pycmp_v`, which already asks the one-sided question through
`PyVarUserObj`. That guard is untouched, and the four ordering rows are in the
fixture as controls.

The non-bool rows are a real and separate defect, in `pycmp_v` rather than in
the eight arithmetic entry points: ordering owes a THREE-WAY answer, and
coercing that out of the dunder's result is what only a bool survives. Filed by
**lekkerzeilen-c8** as
`bug-n-an-ordering-dunder-that-returns-a-non-bool-fails-against-a-variant-operand`,
prio 40 — deliberately low, because no real ordering dunder returns a non-bool
and that ticket reached the backlog through a fixture rather than through a
program.

**The reason both of us mis-read this is worth keeping.** The peer's ordering
dunders returned marker STRINGS so it could see which one had been called; mine
returned `self.n < q.n`, a bool. That instrumentation choice IS the trigger, so
the same rows disagreed between two honest measurements and neither could see
why. And the message is the other half: `expected a number, got object` is a
statement about the OPERANDS, raised while converting the RESULT — which is what
routed the finding into this ticket in the first place. Third instrument-changed-
what-it-measured in a week; a marker return value is what a fixture author
reaches for by default.

### The parser arm order, not taken

The ordering asymmetry the diagnosis above found is genuine: the blanket variant
arm does claim a pair whose left is a user class declaring the dunder, and the
list-repeat and bytes-repeat arms were deliberately moved ahead of it for
`bug-nilpy-sequence-repeat-with-a-variant-count-falls-through-to-arithmetic`.
It was not changed here, for two reasons and one of them would have been a
reason to change it:

- Every row in the matrix is correct without it, including the reflected forms,
  so there is no behaviour left for it to fix. Its remaining value is the
  RESULT's static type — a compile-time dispatch would type the node with the
  dunder's declared return type instead of `tyVariant` — and that is a typing
  and speed question, not a correctness one. A vector demo doing this per frame
  is the case that would make it worth measuring.
- The arm order in that chain is load-bearing in both directions. In
  `ParseSimpleExpr` the dunder arm has no pylib exclusion, so hoisting it above
  the variant arm would put it above list-concat and dict-union too and route
  `xs + ys` into a `TPyList.__add__` that does not exist. Narrowing the variant
  arm instead (rather than moving anything) is the shape that would work.

Recorded so the next reader knows it was considered and why it is still open:
`refactor-n-user-class-dunders-are-dispatched-at-run-time-when-the-left-operand-is-static`.

### Guard

`test/test_nilpy_variant_operand_arith_dunders.npy` — the existing whole-family
fixture, extended rather than duplicated, because the two arrangements are one
question. The file's opening line, `lhs = 0`, is what made it pass for a year
while half the family was broken: binding a variant on the LEFT and a class on
the RIGHT puts an object in both slots and satisfies the `and`. **A whole-family
fixture that only ever builds the satisfying arrangement certifies the bug.**
Nine new rows, expectations from CPython, the hardest one (no static class on
either side) deliberately not last. Reverted, the fixture dies at the first new
row with the original message; the thirteen original rows still pass reverted,
which is what says the fix did not move the goalposts.

### What it cost the demo

This was the single wall on every lekkerzeilen entry point. After the fix,
`--open-water` under `setarch -R` gets past the camera, through the frame loop's
first pass, and dies somewhere new:
`TypeError: dict.update expects a mapping or an iterable of pairs`.
- 2026-09-14 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 56c5e6ea8.
