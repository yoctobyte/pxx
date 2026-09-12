---
track: N
prio: 45
type: bug
blocked-by: []
summary: "A class-level attribute holding a CONTAINER (`T = (1, 2)`, `L = [3, 4]`) reads back EMPTY through `self` from a method declared EARLIER in the class body than the attribute — `(4000.0, , , 'x')` where CPython gives `(4000.0, (1, 2), [3, 4], 'x')`. Reading the same two attributes through the CLASS (`NoLambda.T`) is CORRECT, and scalars and strings are correct in both positions, so the discriminator is container + read-through-self + declared-below-the-reader. No lambda is involved: measured 2026-09-12 with and without one, identical. PyEmitClassAttrExpr's own comment names the mechanism from the other direction — the member pre-pass 'had only the tokens to go on and defaulted to a variant', and a list or tuple literal yields a CLASS handle, so the retype at the initialiser comes too late for a method already compiled above it."
---

# A container class attribute declared after a method is empty through `self`

## Measured, 2026-09-12

```python
class NoLambda:
    def read(self):
        return (self.F, self.T, self.L, self.S)

    F = 4000.0
    T = (1, 2)
    L = [3, 4]
    S = "x"
```

| | CPython | pxx |
| --- | --- | --- |
| `NoLambda().read()` | `(4000.0, (1, 2), [3, 4], 'x')` | `(4000.0, , , 'x')` |
| `NoLambda.T`, `NoLambda.L` | `(1, 2)` `[3, 4]` | `(1, 2)` `[3, 4]` — correct |
| the same class with the attributes ABOVE `read` | correct | correct |

So three things have to line up: a CONTAINER value, read through `self`, from a
method that appears ABOVE the declaration. Change any one and it is right, which
is why an ordinary fixture never sees it — attributes are normally written at the
top of a class body.

A lambda in the class makes no difference (checked both ways). That matters
because this was FOUND while fixing a different defect with the same symptom —
`bug-n-a-class-level-attribute-loses-its-value-when-a-method-holds-a-lambda`,
fixed by parking the hoist queue — and the two must not be conflated: that one
loses every type including scalars and depends on a lambda; this one loses only
containers and depends on declaration order.

## Where to look

`PyEmitClassAttrExpr` (`compiler/pyparser.inc` ~7000) documents the mechanism
from the other side:

> RETYPE the field to what the initialiser actually produced. The pre-pass had
> only the tokens to go on and defaulted to a variant; a list or dict literal
> yields a CLASS handle, and storing one into a variant slot left the tag
> garbage — `Cfg().LIMITS[1]` read None.

A method compiled ABOVE the initialiser is compiled against the pre-pass's
variant typing, and the retype happens afterwards. The candidate fix is to let
the pre-pass recognise a container LITERAL from its first token (`(`, `[`, `{`)
rather than defaulting to a variant — it already walks the tokens — so the field
is typed before any method body reads it. Not attempted here.

## The fixture that exists and deliberately does NOT assert this

`test/test_nilpy_class_attribute_and_a_lambda_in_a_method.npy`'s `Below` class is
the declared-after arrangement and carries scalars and a string only. Its
docstring says why and points here. Adding a container row there would tie that
fixture to this bug and redden it whenever either moved.
