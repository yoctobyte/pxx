---
track: A
prio: 30
type: bug
blocked-by: []
status: backlog
summary: "`VarClear(v)` is `error: undefined variable (VarClear)`, though FPC's Variants unit exports it and code that resets a Variant slot uses it. The runtime primitive already exists -- PXXVarClear is implemented and exported from builtinheap.pas -- so this is a missing declaration, not missing machinery."
---

# `VarClear` is undefined

Found 2026-08-24 while measuring the Variant renderers for
[[bug-a-a-boolean-variant-writes-as-1-or-0-off-x86-64]]: the empty-slot row of
the differential could not be written from Pascal at all.

```pascal
uses variants;
var v: Variant;
begin
  v := 'hey';
  VarClear(v);         { pascal26: error: undefined variable (VarClear) }
  writeln('[', v, ']');
end.
```

FPC compiles it and prints `[]`.

## Why it should be cheap

The primitive is already there and already correct: `PXXVarClear(v: Pointer)`
is implemented in `compiler/builtin/builtinheap.pas` and declared in its
interface, and the compiler emits calls to it (that is what releases a managed
payload when a variant slot is overwritten). What is missing is the
user-callable `VarClear` in front of it.

Check `lib/rtl/variants.pas` first — the neighbouring entry points (`VarType`,
`VarIsNull`, `VarAsType`) live there and one of them is the pattern to copy.
Grep the FPC Variants interface for the rest of the family while you are in
there rather than filing this again per name: `VarIsEmpty`, `VarIsClear`,
`VarToStr` and `VarArrayCreate` are the likely siblings, and
`devdocs/dev/normalise-dont-special-case.md` is explicit that fixing one arm of
a list without checking the others is how the second one stays broken.

## Gate

Track A's, plus the program above matching FPC on x86-64 and one cross target,
plus whichever siblings the grep turns up.
