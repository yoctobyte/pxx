---
slug: bug-p-a-typed-constant-initialiser-accepts-only-a-string-literal
title: "A string-typed constant/variable initialiser demands a LITERAL token, so a named constant on the right-hand side is refused"
track: P
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-05
found-by: frankA
summary: "`const s1 = 'String1'; const A: array[0..0] of shortstring = (s1);` is refused with `array constant: expected a string or char literal`, and the scalar twin `const X: shortstring = s1` with `typed string constant: expected a string or char literal`. Three sites ask `CurTok.Kind <> tkString` and none of them consults FindStrConst, whose table already holds exactly the (SOffset, SLen) span they want. Blocks conformance rows tstring3 and tinterface6."
---

# The shape

```pascal
const
  c1 = 'A';            { a one-character untyped const -> a CHAR const }
  s1 = 'String1';      { a multi-character one         -> a StrConst span }
resourcestring
  R1 = 'Res1';         { a VARIABLE with storage, not a const at all }
const
  A : array[0..1] of shortstring = (s1, s1);   { array constant: expected a string or char literal }
  B : shortstring                = s1;          { typed string constant: expected a string or char literal }
```

FPC accepts all of these. `tstring3.pp` is the array form over all three source
kinds at once; `tinterface6.pp` is the scalar form with a CORBA interface name
on the right (its string UID).

# Where

Three sites, one concept, all spelled `if CurTok.Kind <> tkString then Error(...)`:

- `pasparser_decl.inc` ~2040 — an element of a VAR-section array initialiser
- `pasparser_decl.inc` ~2741 — an element of a CONST-section array constant
- `pasparser_decl.inc` ~2958 — a scalar typed string constant

Each then does `scOff := Tokens[TokPos-1].SOffset; scLen := ...; Next;` and
records a Kind=1 (string-literal span) init. **The span is the only thing they
need**, and `FindStrConst(name)` already returns a row carrying `StrConstSOff` /
`StrConstSLen` — the identical pair. So the fix is a shared
`TakeStrLitSpan(var scOff, scLen): Boolean` that accepts a `tkString` token OR a
`tkIdent` naming a StrConst, used at all three sites.

Three copies of one predicate is the smell `normalise-dont-special-case.md`
names; the helper should replace them rather than growing a fourth arm.

# Three sources, and only ONE of them is a StrConst

This is the part to measure before writing code, because the ticket that says
"accept an identifier" is under-specified:

| written | how it is stored | what the sites need |
| --- | --- | --- |
| `const s1 = 'String1'` | StrConst row: name + source span | the span — free |
| `const c1 = 'A'` | a CHAR const (`AddConst(name, tyChar, ord)`) — deliberately, `bug-pascal-ord-of-a-one-char-string-const-is-its-address` | an ORDINAL, so it needs a char->string init kind, not a span |
| `resourcestring R1 = 'Res1'` | a real initialised VARIABLE (`DeclareInitialisedStringVar`) — FPC's runtime-replaceable resourcestring | a copy of the variable's value at init time, which is a different init kind again |

`tstring3` uses all three in one program, so it does not close until all three
are handled. The scalar form (`tinterface6`) closes on the first row alone.

Do not read "one-character constants are char" as a defect on the way past —
it is deliberate and has its own ticket's worth of evidence behind it.
