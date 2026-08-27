---
track: N
prio: 70
type: bug
blocked-by: []
summary: "`self.v = n / 2` with `n: int` declares an Int64 field and prints 4612811918334230528; `self.v = n + 1.5` prints the same class of garbage. The `self.NAME = expr` pre-pass types the field from the FIRST token of the right-hand side — the parameter, or the leading literal — and only reaches the expression scanner when that first token says nothing."
status: done
owner: agent-A
---

# A field takes its type from the FIRST TOKEN of a multi-token right-hand side

- **Type:** bug (Track N — Nil Python frontend) — silent wrong value.
- **Filed:** 2026-08-26 by frank1-N-truediv, while fixing
  [[bug-n-inferred-return-type-of-true-division-is-int]]. The division fix
  landed and the *return* shapes went green; these FIELD shapes did not, and
  varying the shape showed why: division is not what they are about.

## Repro

```python
class A:
    def __init__(self, n: int):
        self.v = n / 2          # CPython 2.5   pxx 4612811918334230528
    def get(self):
        return self.v

class B:
    def __init__(self):
        self.v = 7 / 2          # CPython 3.5   pxx 4615063718147915776
    def get(self):
        return self.v

class F:
    def __init__(self, n: int):
        self.v = n + 1.5        # CPython 6.5   pxx 4619004367821864960
    def get(self):
        return self.v

print(A(5).get()); print(B().get()); print(F(5).get())
```

`4612811918334230528` is `0x4004000000000000` — 2.5's IEEE-754 bits read as an
Int64. The value is computed correctly and stored into an integer-typed field.

## Cause — not division, the first token

`F` is the one that settles it: **no division anywhere**, same garbage. The
`self.NAME = ...` field pre-pass in `compiler/pyparser.inc` (the
`PyFindSuiteIndent` walk, ~line 30930) tries its scanners in this order:

1. a QUALIFIED construction `tk.Canvas(...)`,
2. `PyHeaderParamType(methodStart, j, GetTokenStr(rhsAt))` — the right-hand
   side's **first token** as a parameter name,
3. `PyTypeFromTokenIndex(rhsAt)` — the **first token** as a literal/type name,
4. `PyInferExprType(rhsAt, endOfLine)` — the real expression scanner, reached
   **only if all of the above said tyUnknown**.

So `n / 2` and `n + 1.5` are typed by `n` alone, and `7 / 2` by the `7`. The
expression scanner — which since the truediv fix answers both correctly — never
runs.

This is the exact lesson already recorded three files up, in
`PyBlkRhsEndsAt`'s own header comment: *"the depth>0 arm's safe-shape tests each
looked at the FIRST token of the right-hand side and nothing else, so `wrapped =
"a-b".split("-")` matched the STRING-LITERAL shape."* The module-global arm of
this very pre-pass already calls `PyBlkRhsEndsAt`. The two first-token scanners
next to it do not.

## Fix shape — and the hazard that makes the naive reorder wrong

The obvious fix ("run `PyInferExprType` first") re-opens
`bug-nilpy-str-of-object-segfaults-when-dunder-builds-a-string`:
`PyInferExprType`'s token walk maps an identifier that names a class to
`tyClass` **case-insensitively**, and has no parameter-shadowing check of its
own. `self.node = node.next` inside `class Node` would then type the field as a
Node again — the segfault that arm 2 exists to prevent. That is why this was
filed rather than folded into the truediv fix.

Two shapes that do work:

- **Guard arms 2 and 3 with `PyBlkRhsEndsAt(rhsAt)`** — a first-token answer is
  a claim about that token, so let it decide only when that token IS the whole
  right-hand side — and keep them as the FALLBACK when `PyInferExprType`
  returns `tyUnknown`, so nothing that resolves today stops resolving.
- Or give `PyInferExprType` the parameter-shadowing check the return scan
  already has (`PyNameBoundInDef`) and then reorder freely. Larger, but it fixes
  the shadowing hole for every caller instead of routing around it.

Prefer the second if the shadowing check is cheap to lift; the first is the
small safe move.

## Gate

A `.npy` diffed against CPython covering all three repro classes **plus** the
single-token controls that must not change: `self.node = node` inside `class
Node` (the shadowing case), `self.x = param`, `self.xs = [1, 2]`,
`self.t = tk.Text(...)`, and a field assigned from a module global.

## Fixed 2026-08-27 — option 1, and the named hazard did not materialise

Took the ticket's **first** shape: guard the two first-token readers with
`PyBlkRhsEndsAt(rhsAt)` so they decide only when that token IS the whole
right-hand side, and keep them, unguarded, as the FALLBACK after
`PyInferExprType` — so nothing that resolved before this change stops resolving.

The ticket recommended the second shape (lift `PyNameBoundInDef` into
`PyInferExprType`) if the shadowing check were cheap to lift, on the grounds
that option 1 leaves `self.node = node.next` inside `class Node` exposed. **That
hazard was measured and does not occur**: `self.node = node.v` and
`self.tail = node.next` inside a program declaring `class Node` both answer
correctly at HEAD with this fix. The wider change is therefore not justified by
the reason given for it — if it is wanted, it wants its own repro.

What the control DID find is a real pre-existing segfault with nothing to do
with shadowing: a NilPy class named **`Text`** dies on every field shape,
including a single-token right-hand side, and works the moment it is renamed.
Filed as
[[bug-n-a-class-named-text-still-segfaults-outside-the-qualified-construction-arm]].

## Fixed in the same change

[[bug-n-a-field-typed-across-a-semicolon-takes-the-next-statements-type]] — the
right-hand side's span ran to end-of-LINE, not end-of-STATEMENT, so
`self.items = items; self.i = 0` typed the field from the `0`. It is the same
span this ticket's arms read, computed once now with `tkSemicolon` in the
terminator set, so the two cannot drift apart again.

## Verified against the CPython oracle

`test/test_nilpy_field_type_from_whole_rhs.npy` (+ `.expected` generated by
CPython), registered in `test-core`: the three repro classes (`n / 2`, `7 / 2`,
`n + 1.5`) plus every control this ticket's Gate section named — a parameter
shadowing a class name (`class Node` / `self.node = node`), `self.x = param`,
`self.xs = [1, 2]`, a field from a module global — and the two semicolon shapes.
GREEN at HEAD; at `pinned` three rows print IEEE bit patterns and the program
then dies.

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
