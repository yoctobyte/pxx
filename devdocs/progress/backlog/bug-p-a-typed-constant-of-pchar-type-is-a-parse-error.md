---
track: P
prio: 35
type: bug
blocked-by: []
status: backlog
summary: "`const KC: PChar = 'konst';` is `error: unexpected token` -- a TYPED constant whose type is a pointer does not parse. FPC takes it, and it is the ordinary way to name a C string constant. Untyped `const KC = 'konst';` works, and so does a `var` of the same type."
---

# A typed constant of PChar type is a parse error

Found 2026-08-24 while writing the differential for
[[bug-p-a-string-literal-assigned-to-a-pchar-is-empty]] — the const row had to
be deleted from the test program before pxx would compile it at all.

```pascal
const KC: PChar = 'konst';
begin
  writeln(KC);
end.
```

```
Expected: begin, but got: konst (Kind: 3, Line: 1)
pascal26:1: error: unexpected token
```

FPC compiles it and prints `konst`.

A LOUD failure, not a silent one, which is why the prio is 35 rather than
alongside its parent. But `const S: PChar = '...'` is the ordinary way to name
a C string constant, so any real binding header hits it on the first line.

## Where to look

The typed-constant path in `compiler/pasparser_decl.inc` — `const NAME: T = value`.
It evidently accepts the ordinal and string type kinds and not a pointer one.
Check the whole shape family before fixing one arm:

- `const P: PChar = 'text'` (this ticket)
- `const P: Pointer = nil`
- `const A: array[0..1] of PChar = ('a', 'b')`
- `const R: TRec = (f: 'x')` where the field is a PChar

and note that whatever accepts the initialiser must apply the same `+8`
character-data skip the ASSIGNMENT path just gained, or this will parse and
then be empty — the identical defect one construct over.
`devdocs/dev/normalise-dont-special-case.md`: fixing one arm of a double case
without grepping for the sibling is how the second one stays broken.

## Gate

Track P's, plus the program above matching fpc 3.2.2 on x86-64 and one cross
target, plus whichever siblings the shape family turns up.
