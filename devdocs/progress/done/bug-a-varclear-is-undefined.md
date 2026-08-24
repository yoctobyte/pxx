---
track: A
prio: 30
type: bug
blocked-by: []
status: done
summary: "`VarClear(v)` is `error: undefined variable (VarClear)`, though FPC's Variants unit exports it and code that resets a Variant slot uses it. The runtime primitive already exists -- PXXVarClear is implemented and exported from builtinheap.pas -- so this is a missing declaration, not missing machinery."
owner: claude-A
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

## Fixed 2026-08-24 (claude-A), with its siblings in the same pass

`VarClear`, `VarIsClear`, `VarToStr` and `VarToStrDef` are now exported from
`lib/rtl/variants.pas`. Ten rows against fpc 3.2.2, byte-identical on x86-64,
i386, aarch64 and arm32 -- and identical under **`pinned`** as well as HEAD,
which was the design constraint, not a bonus (see below).

Both this ticket and [[bug-b-vartostr-is-missing-from-variants]] said to check
the family rather than file it again per name
(`devdocs/dev/normalise-dont-special-case.md`), so they were done together.

### VarClear is an ASSIGNMENT, deliberately

`V := Unassigned`, not a call to `PXXVarClear` and not `Finalize(V)`.

Assigning a Variant already releases the destination's old payload before
storing -- `IR_VAR_STORE` owns the ARC-correct 16-byte copy -- and `Unassigned`
is a `VT_EMPTY` slot that nothing ever writes to. So the assignment is
Finalize's definition down to both load-bearing properties: it drops a
REFERENCE rather than the object (the gated test's 2000-round loop proves a
second owner survives), and a second `VarClear` releases an empty and
decrements nothing.

`Finalize(V)` says exactly the same thing and became legal on a bare Variant
earlier the same day ([[feature-a-finalize-for-bare-dynarray-and-variant]]) --
but only on a compiler **newer than the current pin**, and this unit is Track
B's ground, built with `$(PXX_STABLE)`. Using it would have broken
`make lib-test` for every other lane until someone ran a pin. The assignment
needs nothing new and works on both.

That constraint is also why this landed under Track A despite the file being
Track B's: the fix had to be reasoned about against an unpinned compiler
capability to know it must NOT be used.

### Gate

`tools/gate.sh quick` GREEN; new `lib-test` case
`test/lib_variants_surface.pas` built with `$(PXX_STABLE)`, matching fpc 3.2.2
exactly; the same program cross-checked on i386 / aarch64 / arm32 under
qemu-user.

## Log
- 2026-08-24 — resolved, commit b4bfe770f.
