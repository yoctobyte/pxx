---
track: N
prio: 45
type: bug
blocked-by: []
summary: "FIXED 2026-09-13 (647c3cbdb). A class attribute whose initialiser is an EXPRESSION rather than a single literal token was recorded as a variant by the member pre-pass and only retyped later by PyEmitClassAttrExpr, so any method declared ABOVE the attribute was compiled against the variant and read it wrong. Containers read EMPTY (`(4000.0, , , 'x')` against CPython's `(4000.0, (1, 2), [3, 4], 'x')`); reading through the CLASS, or declaring the attribute above the reader, was correct. THE ORIGINAL CONTAINER-ONLY FRAMING WAS TOO NARROW — `P = (1 + 2)`, a scalar, reads None in the same arrangement; that half is NOT fixed here and is filed as bug-n-a-scalar-expression-class-attribute-declared-after-a-method-reads-none. Fix asks PyInferExprType in the pre-pass, restricted to tyClass WITH a resolved rec: taking its scalar answer segfaults (field narrows, store path still writes wide) and tyClass+REC_NONE segfaults on `self.L[0]` where the variant raised a clean TypeError. Ident-call containers (`dict(b=2)`) remain unfixed, also pre-existing."
status: done
---

# An EXPRESSION class attribute declared after a method reads wrong through `self`

> **FIXED 2026-09-13 (647c3cbdb) for the container half.** Read the dated
> section at the foot before the 2026-09-12 material above it: the
> container-only framing below was the original premise and is superseded.
> The scalar half is a separate open ticket.

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

> **SUPERSEDED 2026-09-13.** The first of those three is wrong. It is not a
> CONTAINER value, it is an initialiser that is an EXPRESSION rather than a
> single literal token — `P = (1 + 2)` fails the same way, reading None. And
> the claim in the original summary that "scalars and strings are correct in
> both positions" holds only for SINGLE-LITERAL scalars, which reach the
> pre-pass's constant branch. Measured at HEAD and under pin v408.

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
variant typing, and the retype happens afterwards.

> **The candidate fix recorded here — recognise a container literal from its
> first token `(`, `[`, `{` — was WITHDRAWN by its author 2026-09-13 and must
> not be revived.** It cannot work: `(1, 2)` is a TPyList and `(1 + 2)` is an
> integer, and both open with tkLParen, so a first-token test types the
> parenthesised scalar as a container. What landed instead asks
> PyInferExprType, which the file's other pre-passes already trust — the same
> authority as the retype rather than a second one that can disagree with it.

## The fixture that exists and deliberately does NOT assert this

`test/test_nilpy_class_attribute_and_a_lambda_in_a_method.npy`'s `Below` class is
the declared-after arrangement and carries scalars and a string only. Its
docstring says why and points here. Adding a container row there would tie that
fixture to this bug and redden it whenever either moved.


## FIXED 2026-09-13 (frankZ, 647c3cbdb) — and the premise was corrected on the way

**The instrument that settled it.** One field read by TWO methods, one above the
declaration and one below, in a single program: `TwoReaders` with `C = [5, 6]`
between them returned empty from `early()` and `[5, 6]` from `late()`. One
field, two answers, by method compile order — which proves the typing is
per-method and not a property of the field. Any single arrangement leaves that
ambiguous.

**The premise correction.** The container framing above is too narrow. The rule
is ANY initialiser that is an EXPRESSION rather than a single literal token,
because only a single literal token followed by end-of-line reaches the
pre-pass's constant branch. `P = (1 + 2)` reads None in the same arrangement,
at HEAD and under pin v408 alike. Filed as
`bug-n-a-scalar-expression-class-attribute-declared-after-a-method-reads-none`
rather than as a section here, because a scalar reading None is a different
population from a container reading empty and a section inside a
container-titled ticket gets closed by whoever fixes containers.

**What landed.** The member pre-pass asks `PyInferExprType` for an expression
initialiser's type, restricted two ways. Both restrictions were measured by
breaking them first, and both are recorded in the code comment so the next
reader does not re-derive them:

1. **tyClass only.** `(1 + 2)` infers tyInt64; typing the field that way
   SEGFAULTED — the slot narrows while the store path still writes the wide
   value. The pinned compiler merely read None, so widening this is a
   regression rather than an improvement, and the scalar ticket's fix belongs
   in the STORE path.
2. **Never tyClass without a resolved rec.** tyClass + REC_NONE segfaulted on
   `self.L[0]`, where the variant it replaced raised a clean
   `TypeError: object is not subscriptable`. A crash is worse than a diagnosed
   refusal, so a shape whose class cannot be named stays a variant.

**Still unfixed, both verified already broken under pin v408:** ident-call
containers (`dict(b=2)`), and the scalar case. Mapping builtin constructor
names to recs would be exactly the second mechanism this fix exists to avoid —
the real remedy is a rec-returning inference.

**Verification.** Fixture `test_nilpy_class_attribute_declared_after_a_method`
is in the FAILING arrangement, byte-identical to CPython at HEAD, and verified
to FAIL on pin v408 (empty containers, then TypeError) — a fixture that passes
on the unfixed compiler guards nothing. Full `test-nilpy` tier EXIT=0,
`gate.sh quick` GREEN, self-host fixedpoint converged. Re-verified after
pulling `152b316c1`, which adds a lone-`None` arm to `PyInferExprType` and is
therefore an INPUT to this fix: all probe shapes unchanged, and
`None`-containing containers (`[None, 1]`, `(None, 2)`, `{"k": None}`) match
CPython including traversal.

## Log
- 2026-09-13 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 22b7319f1.
