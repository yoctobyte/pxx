---
slug: bug-p-a-typed-constant-initialiser-accepts-only-a-string-literal
title: "A string-typed constant/variable initialiser demands a LITERAL token, so a named constant on the right-hand side is refused"
track: P
prio: 35
type: bug
status: done
owner: ""
created: 2026-09-05
found-by: frankA
summary: "FIXED 2026-09-05. A typed constant's string initialiser may now NAME an untyped string constant, not only spell a literal: `const s1 = 'S1'; A: array[0..0] of ShortString = (s1);` and the scalar twin `const X: ShortString = s1` both compile, as do all four concatenation combinations. Four sites asked `CurTok.Kind <> tkString` and none consulted FindStrConst, whose table already held the literal's (SOffset, SLen) span -- the exact pair each site captured from the token, so the substitution was a different TABLE and not a conversion. THE CONTROL THAT MADE IT A DEFECT RATHER THAN A MISSING FEATURE: `const n1 = 7; A: array[0..0] of Integer = (n1)` compiled throughout, so named constants were already folded in initialisers and only the STRING path never looked. Fixed with ONE helper (TakeStrInitSpan) plus its copying twin (AppendStrInitText) for the `+` arm, which builds a fresh span instead of pointing at one -- four copies of a token test replaced by two functions, not five copies. Tests byte-identical to fpc 3.2.2, with the integer control as a row and TWO negative controls as `!` steps whose error TEXT is grepped: an undeclared name, and a declared-but-Integer const. The second is the one that fails if the guard is ever loosened from `is a string const` to `is an identifier`.""
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

## Fixed 2026-09-05 (frankB)

`compiler/pasparser_decl.inc`. The ticket's own diagnosis was right and complete
— three sites asking `CurTok.Kind <> tkString` with the span sitting in
`StrConstSOff`/`StrConstSLen` — and there turned out to be a fourth: the `+`
concatenation arm, which consumes CHARACTERS rather than a span and so could not
share the same helper. Fixing only the three would have left
`const s1 = 'a'; X: ShortString = s1 + 'b'` refused while `X: ShortString = s1`
compiled — one arm of a double case, with the sibling one line below.

So: `TakeStrInitSpan` (points at an existing span) and `AppendStrInitText` (builds
a fresh one), and four copies of a token test become two functions rather than
five.

**Why this was a defect and not an unimplemented feature**, which is the
distinction the scope rule turns on: `const n1 = 7; A: array[0..0] of Integer =
(n1)` compiled the whole time. Named constants ARE folded in initialisers. Only
the string path never looked, so the compiler was already holding the text it
said it could not find.

**Both negative controls are `!` steps that grep the error TEXT, not the exit
code.** A refusal has no output to diff, and a step asserting only "it failed"
would pass if the fix made it fail for a new and worse reason. The
declared-but-Integer row (`n1`) is the load-bearing one: an undeclared name is
refused by almost any guard, while `n1` is refused only by a guard that asks
whether the name is a STRING constant — which is exactly what a loosening to
"any identifier" would break, and it would break silently, with every positive
row still green.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 6212b8bae.
