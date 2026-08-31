---
track: N
prio: 40
type: bug
blocked-by: []
summary: "The ~60-line __getitem__/__setitem__ subscript arm exists TWICE, character for character: compiler/pyparser.inc ~38087 and compiler/pasparser_lval.inc ~1290. Which one a NilPy statement reaches depends on which lvalue parser its statement path entered, so a fix applied to one and not the other silently leaves a shape behind. Both copies had to be edited to close the augmented-subscript ticket."
---

# The dunder subscript arm is duplicated verbatim in two lvalue parsers

- **Type:** bug (structural) — **Track N**. **Found:** 2026-08-27 by agent-A
  while closing [[bug-n-an-augmented-subscript-on-a-dunder-class-is-refused]],
  whose fix had to be written twice.

## What

`PyParseLValueAST` (`compiler/pyparser.inc`) and `ParseLValueAST`
(`compiler/pasparser_lval.inc`) each carry the same ~60-line block: the arm that
subscripts a user class through `__getitem__`/`__setitem__`. Same comments, same
error strings, same structure. It is NilPy code — `Nil Python:` messages,
`PyParseBoolExpr`, `FindUMeth(mci, '__getitem__')` — and half of it lives in the
**Pascal** parser, which is a leftover from before the parser split.

## Why it is a defect and not just untidiness

It is a **double case**, and `devdocs/dev/normalise-dont-special-case.md` is
explicit that the second path is the one that stays broken. Concretely:

- the augmented-assignment desugar had to be applied to both copies, and
  applying it to only the first is a change that passes every test you would
  think to run and leaves whichever shapes reach the second copy refused;
- neither copy's comment mentions the other, so grep is the only thing standing
  between a future fix and a half-fix — which is exactly the failure mode
  `meta-track-w-collision-windows-vs-website` records in a different register.

## What is NOT the fix

Deleting the `pasparser_lval.inc` copy on the assumption it is dead. It may well
be — no NilPy shape was found that reaches it during the augmented-subscript
work — but "I could not construct one" is not "there is none", and this arm's
whole history is shapes nobody enumerated
(`bug-nilpy-setitem-without-getitem-write-does-not-compile`,
`bug-nilpy-subscript-read-without-getitem-yields-garbage`).

## Shape of the fix

Extract the block into one routine — `PyParseDunderSubscript(node, mci, var tk,
var recName): Integer` — in `pyparser.inc`, forward-declared in
`pyforwards.inc`, and call it from both sites. The Pascal copy's only real
difference is `ParseExpr` where the NilPy one uses `PyParseBoolExpr`; that is a
parameter, not a reason for a second implementation. Then instrument the
`pasparser_lval.inc` call site once to find out whether it is reachable at all,
and delete it with evidence rather than on a hunch.

Ranked at 40: it produces no wrong answer today (both copies now agree), but it
is a trap primed for the next person who touches either one.

## Gate

`make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, plus
`test_nilpy_augmented_dunder_subscript`,
`test_nilpy_builtin_subclass_dunder_dispatch` and
`test_nilpy_subclass_a_builtin_type` unchanged.
