---
track: A
prio: 30
type: bug
blocked-by: []
status: done
summary: "`string(v)` and `WriteLn(v)` on a Null/Unassigned Variant print `None` in a PASCAL program -- NilPy's spelling of VT_EMPTY leaking into Pascal output. FPC raises EVariantTypeCastError for the cast and prints nothing for the write. Pre-existing (identical under the pinned binary), loud in neither direction: a plausible-looking wrong string."
owner: claude-A
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

## Resolution, 2026-08-24

Question 1 fixed; question 2 filed as
[[decide-should-a-null-variant-raise-like-fpc]] rather than guessed, because
FPC turned out to raise for `WriteLn(a)` as well as for the cast, so "follow
FPC" means making a running program die.

Measured while fixing it, and worth recording: FPC's two empties do NOT behave
alike. `Unassigned` prints and casts as the empty string; `Null` raises in both
contexts. pxx spells both with one `VT_EMPTY` tag, so the empty string is the
only answer one tag can give -- and it is the right one for the spelling the
two implementations can agree on.

The renderer split follows `VariantToCharFPC`'s precedent exactly: a
`VariantToStrPas` that delegates to `VariantToStr` for every tag but the empty
one, selected BY NAME at the lowering seam, so no frontend flag reaches the
runtime. `VariantToStr` itself had to keep saying `None`, because pylib routes
f-strings, `join`, `startswith` and `format` through it -- changing it in place
would have broken `f"{None}"`.

x86-64 needed a second, separate fix: `writeln(v)` there is an INLINE emitter
(`EmitWriteVariant`), not a call, and it wrote `None` from its own data
segment. Every other target already prints nothing, because `PXXWriteVariant`
declined that arm on purpose. Verified after the fix on x86-64, aarch64, arm32
and i386 -- all four byte-identical to fpc 3.2.2. riscv32 cannot compile a
Variant program at all (`unsupported node in IR codegen: var_store`), which is
pre-existing and unrelated.

## Gate

Track A's, plus a differential row per spelling (`string(Null)`,
`string(Unassigned)`, `WriteLn(Null)`) against fpc 3.2.2, and a `.npy` row
proving NilPy still prints `None`.

## Log
- 2026-08-24 — resolved, commit PENDING-COMMIT.
