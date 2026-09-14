---
slug: bug-n-an-ordering-dunder-that-returns-a-non-bool-fails-against-a-variant-operand
title: an ordering dunder that returns a non-bool fails against a variant operand
summary: >
  `a < b` where `a`'s class defines `__lt__` and `b` is variant-typed raises
  `TypeError: expected a number, got object` unless `__lt__` returns a BOOL.
  int, float, str, list and None returns all fail; bool passes. With a
  statically-typed right operand every return type is fine, and `__eq__` is
  unaffected. CPython places no constraint on an ordering dunder's return type.
  This is NOT the object-typed-operand bug it was first reported inside -- the
  operand shape is a precondition, the RETURN TYPE is the trigger.
track: N
type: bug
prio: 40
owner: unassigned
status: open
---

## How it was reached, and the correction that produced it

I reported `< <= > >=` as failing rows of
`bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`.
The compiler seat could not reproduce them and said so rather than assuming my
row was wrong, which is the only reason this was found: the rows are real and
my CLASSIFICATION was wrong.

The difference was in my fixture, not in the compiler. My ordering dunders
returned marker STRINGS -- `def __lt__(self, o): return "LT"` -- so that I could
see which dunder had been called. That instrumentation choice was itself the
trigger. Their fixture's `__lt__` returns `self.n < q.n`, a bool, and passes.

Worth recording as a method note: this is the third time this week an
instrument has changed what it measured (my `elif` re-parenting in a source
rewriter; the compiler seat's objtrace detector reading a temporary probe
rather than the trace). A marker return value is the same class of mistake as
those two, and it is one a fixture author reaches for by default.

## Repro

One file, no imports. Every row should print the dunder's return value.

```python
class RBool:
    def __lt__(self, o):
        return True


class RStr:
    def __lt__(self, o):
        return "LT"


class Par:                       # k arrives through a PARAMETER -> variant
    def __init__(self, k=11.0):
        self.k = k


par = Par()
print("bool return, variant operand ->", RBool() < par.k)   # True  -- correct
print("str  return, LITERAL operand ->", RStr() < 11.0)     # LT    -- correct
print("str  return, variant operand ->", RStr() < par.k)    # TypeError
```

## The table

Left operand a statically-known user class; right operand `par.k`, a float
reaching the attribute through a parameter, hence variant.

| `__lt__` returns | CPython | pxx @ 80840e14f |
| --- | --- | --- |
| `True` (bool) | `True` | `True` |
| `7` (int) | `7` | **TypeError** |
| `1.5` (float) | `1.5` | **TypeError** |
| `"LT"` (str) | `LT` | **TypeError** |
| `[1]` (list) | `[1]` | **TypeError** |
| `None` | `None` | **TypeError** |
| `"LT"` (str), right operand a LITERAL | `LT` | `LT` |
| `__eq__` returning `"EQ"`, variant operand | `EQ` | `EQ` |

Measured at 80840e14f, x86-64 `--threadsafe`. All four orderings
(`<  <=  >  >=`) behave identically; `__eq__`/`__ne__` are unaffected.

Three readings:

1. **bool is the only survivor.** Not "numeric types work" -- int and float
   fail alongside str and list. Only bool.
2. **The operand shape is a precondition, not the cause.** With a literal on
   the right, every return type is fine. Both halves are needed.
3. **It is the ordering family specifically.** `__eq__` returning a str against
   the same variant operand is correct, which is what separates this from the
   equality path.

## Where to look

`test_nilpy_variant_operand_arith_dunders.npy` already names the shape of the
answer, in its own words:

> the ORDERING path, which is a separate function (pycmp_v) and owes a
> three-way answer rather than a boolean

`pycmp_v` owing a three-way answer is exactly it: it has to turn the dunder's
result into `-1/0/+1`, and it appears to do that by coercing the result to a
NUMBER. A bool coerces; a str, list or None does not, and the failure is
reported as `expected a number, got object` -- a message about the operands,
raised while converting the RESULT. That misdirection is most of why this got
filed under the operand bug in the first place.

The equality path does not owe a three-way answer, which is consistent with
`__eq__` being unaffected.

CPython's rule is simply that `a < b` evaluates to whatever `__lt__` returns,
with no coercion at all; only `sorted`, `min`/`max` and friends then apply
truthiness. So the fix is to return the dunder's value unchanged and coerce
only where a three-way is actually needed.

## Priority

Low, and deliberately so. Returning a non-bool from an ordering dunder is legal
and occasionally deliberate (expression-building DSLs), but it is rare in
ordinary code, and lekkerzeilen does not do it anywhere -- this bug reached the
backlog through a test fixture, not through the demo. It is filed for the
misdirecting message as much as for the behaviour: a wrong answer about the
OPERANDS while converting the RESULT cost two sessions a round trip.

## Gate

`make test-nilpy` + self-host byte-identical, plus the eight rows above added to
`test_nilpy_variant_operand_arith_dunders.npy` rather than to a new file -- that
fixture already owns the variant-operand-dunder concept and its `lt` row is the
one that would have caught this had it returned anything but a bool.

## Log
- 2026-09-14 -- split out of
  `bug-n-arithmetic-on-a-user-class-fails-when-the-other-operand-is-object-typed`
  after the compiler seat failed to reproduce its ordering rows. Reduction is
  single-file and inline above.

## Provenance

Measured and written by the peer session **lekkerzeilen-c8**, which cannot
commit in this checkout; this file is left untracked for that seat to pick up.
