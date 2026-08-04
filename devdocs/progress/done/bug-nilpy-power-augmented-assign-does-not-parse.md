---
summary: "NilPy `x **= n` is a hard parse error — power is the one operator with no token, so the token-keyed augmented-assignment machinery cannot express it"
type: bug
track: N
prio: 30
status: done
owner: claude-AN
---

# `x **= n` does not parse

- **Type:** bug (NilPy, hard parse error — loud, not silent) — **Track N**
- **Found:** 2026-08-03, sweeping the in-place operators while closing
  [[bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero]].

## Measured at HEAD

```python
n = 3
n **= 2
print(n)
```
CPython: `9`. pxx: `pascal26:2: error: expected expression`.

Same on a class instance with `__ipow__` declared, and on a class-typed field.
It is the **only** augmented operator still broken: `+= -= *= /= //= %= &= |=
^= <<= >>=` were all swept against CPython in the same run, on a bare name, a
class-typed field and an in-method `self.` target, and all agree.

## Why it is not the ten-line twin it looks like

**Power has no token.** `**` is lexed as two `tkStar` and recognised by an
ad-hoc lookahead (`compiler/parser.inc:13712`, gated on `PyExprMode`), which
lowers it to a `pypow_v` call. So `**=` arrives as `tkStar` then `tkStarEq`, and
neither the lexer nor the parser has anything to hand the augmented path.

That matters because the whole augmented-assignment machinery is keyed on a
binary `TTokenKind`: `PyAugBinTok` maps the compound token to a binary one, and
`PyAugDunderName` maps that to `__ipow__` / `__pow__`. There is no binary token
for power to map *to*, so the dispatch cannot be expressed without either

- adding a real `tkPow` (and `tkPowEq`) and moving the existing `**` lookahead
  onto it — the clean shape, and it also removes an ad-hoc two-token peek; or
- special-casing `tkStar`-then-`tkStarEq` at each augmented site and routing to
  `pypow_v` directly, which adds a fourth spelling of "this is power" and does
  not compose with the dunder ladder.

Prefer the first. Note the token-numbering discipline for a new `TTokenKind`,
and that this is `defs.inc` — shared **Track A** ground, not Track N's own
files, so it needs the sole-A rule and the self-host fixedpoint gate.

## Mind the two-site split

Whichever shape is chosen, an augmented assignment has **two** homes and they
split by token, not by target shape — see
[[bug-nilpy-augmented-assign-to-a-class-typed-FIELD-silently-yields-zero]].
`parser.inc`'s compound-assignment tail intercepts `[tkPlusEq, tkMinusEq,
tkStarEq, tkSlashEq]` for every target; everything else falls through to
`PyParseStatement`. A new `tkPowEq` would fall through to the pyparser site by
default, but a **dotted** target (`h.n **= 2`) reaches `ParseExpr` first, so the
shared tail has to be taught about it too or the field spelling stays broken
while the name spelling works.

## Gate

A `.npy` diffed against CPython: `**=` on an int name, on a float, on a
class-typed name and field with `__ipow__` declared, with only `__pow__`
declared (fall back and rebind), and with neither (catchable TypeError) —
mirroring `test/test_nilpy_augmented_assign_class_field.npy`. Plus self-host
byte-identical, since a new token kind touches `defs.inc`.


## Resolved 2026-08-04 — fixed as part of the grouped statement-forms ticket

Duplicate of item 2 of
[[bug-nilpy-chained-assign-power-assign-and-semicolon-statements]], filed a day
later from a different sweep. Both describe the same defect and, notably, the
same diagnosis: power is the one operator with no token, so the token-keyed
augmented-assignment machinery could not express it.

Fixed in `cd948253b`:

- **`tkPowEq`**, APPENDED at the tail of the token enum (never inserted — the
  ordinals are frozen by the self-host discipline) and lexed before the plain
  `*=` so the longer spelling wins;
- **`PyMakePow`**, the `**` lowering factored out of `ParseFactor` so the
  augmented spelling builds the IDENTICAL node. A second hand-built `pypow_v`
  call would have compiled fine and silently dropped the `__pow__`/`__rpow__`
  dunder dispatch;
- the **result widens**: `2 ** 3` is an int and `2 ** -1` is a float, so the
  target must not keep its type. Inside a def the trial parse notes that from
  the lowered node; at MODULE scope it needed a token-shape arm beside the one
  `/=` already had — measured, not assumed.

Re-measured at HEAD: `x = 3; x **= 2` prints `9`, matching CPython. Covered by
`test/test_nilpy_chained_assign_powassign.npy`, which exercises int, negative
and float exponents at both module and def scope.

## Log
- 2026-08-04 — resolved (duplicate; fixed by cd948253b).
- 2026-08-04 — resolved, commit 5ffd33a0b.
