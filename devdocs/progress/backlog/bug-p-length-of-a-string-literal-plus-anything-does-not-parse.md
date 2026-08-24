---
track: P
prio: 40
type: bug
blocked-by: []
status: backlog
owner: ""
summary: "`Length('ab' + s)` is a PARSE ERROR (`Expected: ), but got: +`). Length's compile-time fold for a string literal fires on the first token being tkString and immediately demands `)`, so a literal that is merely the LEFT OPERAND of a concat is mistaken for the whole argument. `Length(s + 'ab')` works, and `Length(('ab') + s)` works — the same expression, three spellings, one of them refused."
---

# `Length('literal' + x)` does not parse

Found 2026-08-24 while writing an unrelated differential; the test line
`if Length(keep) <> Length('payload-' + IntToStr(i)) then` would not compile.

```pascal
var s: AnsiString; n: Integer;
s := 'q';
n := Length('ab' + s);      { pascal26: error: unexpected token (near 'ab' >>> s)  fpc: 3 }
n := Length('ab' + 'cd');   { same error                                            fpc: 4 }
n := Length(s + 'ab');      { OK — 3 }
n := Length(('ab') + s);    { OK — 3 }
n := Length('ab');          { OK — 2 }
```

## Root cause — an exact line

`compiler/pasparser_expr.inc`, in the `Length` intrinsic arm:

```pascal
{ Length of a string LITERAL folds to its char count at compile time }
if CurTok.Kind = tkString then
begin
  node := AllocNode(AN_INT_LIT);
  ASTIVal[node] := Length(CurTok.SVal); ASTTk[node] := Ord(tyInteger);
  Next; Expect(tkRParen, ')');       { <-- assumes the literal was the WHOLE argument }
  CurASTNode := node;
  Exit;
end;
```

The fold is right; its GUARD is wrong. It tests "the argument STARTS with a
string literal" and concludes "the argument IS a string literal". One token of
lookahead settles it:

```pascal
if (CurTok.Kind = tkString) and (Tokens[TokPos].Kind = tkRParen) then
```

Anything else falls into the `ParseExpr` path just below, which already handles
a concat r-value (the comment there says so: "a non-lvalue managed-string value
(concat / function result) lowers as a value"). That is why the parenthesised
and right-hand spellings work — they never reach the fast path.

This is the [[normalise-dont-special-case]] shape exactly: one concept
(`Length` of a string expression) with a fast path that is not a strict subset
of the general one.

## Grep the sibling first

`High` has the same class of defect one layer worse, and it is ten lines above
in the same file:

```pascal
if CurTok.Kind <> tkIdent then Error('High: expected array variable or ordinal type');
```

so `High('ab' + s)` — legal in fpc 3.2.2, which answers 3 — cannot be written at
all, and neither can `High(f(x))` or any other non-ident string expression. That
is a wider gap than the Length guard (it needs the r-value path High does not
have, not just a better guard), so it may want its own ticket; decide when
fixing this one, and do not close this one without looking.

## Gate

Track P's, plus the five rows above in a test wired into `test-core`, each
diffed against fpc 3.2.2 rather than reasoned about — including the two that
already work, since the fix moves them onto a different path.
