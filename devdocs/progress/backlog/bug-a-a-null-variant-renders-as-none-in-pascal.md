---
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "`string(v)` and `WriteLn(v)` on a Null/Unassigned Variant print `None` in a PASCAL program -- NilPy's spelling of VT_EMPTY leaking into Pascal output. FPC raises EVariantTypeCastError for the cast and prints nothing for the write. Pre-existing (identical under the pinned binary), loud in neither direction: a plausible-looking wrong string."
---

# A Null Variant renders as `None` in a Pascal program

Found 2026-08-23 while fixing
[[bug-a-null-does-not-propagate-through-variant-arithmetic]]; unrelated to that
defect and present in the pinned binary too, so pre-existing.

```pascal
uses variants;
var a: Variant;
begin
  a := Null;        WriteLn('[', string(a), ']');   { pxx: [None]   fpc: raises }
  a := Unassigned;  WriteLn('[', string(a), ']');   { pxx: [None]   fpc: raises }
  a := Null;        WriteLn(a);                     { pxx: None }
end.
```

FPC's answer for the CAST is
`EVariantTypeCastError: Could not convert variant of type (Null) into type
(String)`.

## Why `None`

`VT_EMPTY` is one tag serving three spellings: Pascal's `Null`, Pascal's
`Unassigned`, and NilPy's `None`. The variant-to-string path renders that tag
with Python's word for it, which is right in a `.npy` program and wrong in a
`.pas` one. The renderer needs the same language split every other
Pascal-vs-NilPy variant divergence already uses (`PyProgramMode` at emit time /
choosing which helper to call), not a new tag.

## Scope note

Two questions, and only the first is clearly settled:

1. **Which text.** `None` is wrong for Pascal. `''` is the obvious substitute.
2. **Whether to raise instead.** FPC raises on the explicit `string(v)` cast.
   Whether pxx should follow is a `--strict-fpc`-shaped question rather than an
   obvious yes -- CLAUDE.md's rule is that strict flags govern how source is
   COMPILED and how output is FORMATTED, and this is formatting, so it is in
   scope for the flag; but making an unqualified cast raise by default changes
   what compiles today into what dies today. If the answer is not obvious to
   whoever picks this up, file a Track U `decide-` rather than guessing.

Rendering a Null as the empty string is safe on its own and does not need that
question answered.

## Gate

Track A's, plus a differential row per spelling (`string(Null)`,
`string(Unassigned)`, `WriteLn(Null)`) against fpc 3.2.2, and a `.npy` row
proving NilPy still prints `None`.
