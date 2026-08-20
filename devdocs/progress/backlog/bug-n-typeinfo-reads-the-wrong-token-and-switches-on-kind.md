---
track: N
prio: 30
type: bug
blocked-by: []
summary: "NilPy's TypeInfo path carries the same two defects Track A just fixed on the Pascal side: it reads GetTokenStr(TokPos) — one token PAST the type name, because Next already advanced — and it resolves the type from the TOKEN KIND rather than the spelling, so TypeInfo(byte) answers Integer (byte and integer share tkInteger_T)."
status: backlog
owner: unassigned
---

# N TypeInfo reads the wrong token and switches on token kind

- **Track N** (`compiler/pyparser.inc`, the `AN_TYPEINFO` parse around line 42435).
- Sibling of the Pascal-side fix in `compiler/pasparser_expr.inc`
  (`feature-typeinfo-all-types`, landed on Track A). Filed rather than fixed:
  `pyparser.inc` is Track N's file and N work is currently deferred, so this is
  a hand-off, not a half-applied change.

## The two defects, both visible in one 17-line block

```pascal
tiName := GetTokenStr(TokPos);      { (1) off by one }
case CurTok.Kind of                 { (2) resolves by KIND, not spelling }
  tkInteger_T:  tiTk := tyInteger;
  tkBoolean_T:  tiTk := tyBoolean;
  ...
```

**(1) off by one.** `lexer.inc`'s `Next` reads `Tokens[TokPos]` and *then*
does `Inc(TokPos)`, so by the time this line runs `TokPos` already points at
the `)` after the type name. `tiName` is therefore `)`, not the type. It has
been invisible because `tiName` feeds only the
`'TypeInfo is not supported for type: '` error, and every branch that reaches
that error had already failed to assign a kind — so the wrong string only ever
showed up inside a message nobody diffed. The Pascal copy now reads
`GetTokenStr(TokPos - 1)`.

**(2) kind, not spelling.** `byte` and `integer` both lex as `tkInteger_T`
(two spellings, one token kind — see `lexer.inc`), as do the other
width-variant ordinals. Switching on `CurTok.Kind` therefore collapses them:
`TypeInfo(byte)` answers `Integer`. The Pascal copy now tries
`OrdinalNameToTk(tiName)` **first** and falls back to the kind switch only
when the spelling does not resolve.

## Why it is a real N bug, not a divergence

NilPy is upward compatible with CPython, but this is not a CPython-parity
question at all — it is a wrong *answer* from a construct NilPy accepts and
compiles. A program that branches on the reported type takes the wrong branch.

## Fix

Port both halves from `compiler/pasparser_expr.inc` (search `tiName`):
`TokPos - 1`, then `OrdinalNameToTk` before the `case`. Keep the explanatory
comments — the off-by-one is the kind of thing that gets "cleaned up" back into
existence.

## Gate

`make test-nilpy` green + self-host byte-identical, per Track N's lane rules.
A `.npy` assertion in the same shape as
`test/test_typeinfo_scalar_names.pas` (assert the byte-vs-integer pair, since
that is the case the kind switch cannot express) is the test that bites.
