---
slug: bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering
title: "SetLength through a string cast of a Pointer slot has no lowering, in EITHER spelling"
track: P
prio: 45
type: bug
status: working
found: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
summary: "FIXED 2026-09-06, and MY OWN PREDICTION IN THIS TICKET WAS WRONG: I said ir.inc with five per-target twins; the fix is two guards in pasparser_stmt.inc and one case label in NodeIsManagedString, zero backend arms. `var p: Pointer; AnsiString(p) := 'abc'; SetLength(AnsiString(p), 2)` was refused with `SetLength expects a string variable in IR codegen`; fpc 3.2.2 -Mdelphi accepts it and prints `ab`. SPLIT OUT OF bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer, which bundled it as requirement 2 -- and it is NOT an alias defect: measured, the ALIAS spelling `SetLength(t(p), 2)` and the BUILT-IN spelling fail identically, so the alias is not part of the cause. The parser drops the cast (pasparser_stmt.inc, slCastDrop) and hands the classifier a Pointer SYMBOL, which is neither an array nor a managed string, so the target is classed as a frozen string and codegen refuses. Forcing the other classification was tried and answers `SetLength expects an ARRAY variable` -- so neither arm has a lowering for a pointer-held string and this is an ir.inc job, with FIVE per-target twins of the refusal."
---

# `SetLength` through a string cast of a `Pointer` slot has no lowering, in either spelling

## Measured 2026-09-06 against `fpc 3.2.2 -Mdelphi`

```pascal
var p, q: Pointer;
type t = AnsiString;
begin
  t(p) := 'abc';           SetLength(t(p), 2);            { pxx: refused   fpc: ab }
  AnsiString(q) := 'abc';  SetLength(AnsiString(q), 2);   { pxx: refused   fpc: ab }
end.
```

`pascal26: error: SetLength expects a string variable in IR codegen`, both.

## Why it is its own ticket

It arrived as requirement 2 of
[[bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer]],
whose other three requirements are fixed and whose subject is the ALIAS spelling
diverging from the built-in one.

**This half does not diverge — both spellings fail, identically.** So the alias
is not in the cause at all, and bundling them would have meant closing an alias
ticket on a fix that had nothing to do with aliases. The read and store halves
of that ticket were exactly a two-spellings-one-taught seam; this one is a
missing lowering that both spellings reach.

## Where it gives up, measured rather than read

1. `pasparser_stmt.inc`'s `SetLength` arm sets `slCastDrop` for any string-typed
   cast around the target and **drops** it, so the classifier below sees the
   bare `p`.
2. `p` is a `Pointer` symbol: not `IsArray`, `TypeKind` is not `tyAnsiString`.
   So `slIsArrTarget` stays False, the target is classed as a **frozen string**,
   and codegen refuses two phases later.
3. **CORRECTED 2026-09-06 by the fix itself — the conclusion drawn from this
   probe was wrong.** The probe result is real and the inference from it was
   not: forcing the classification alone does not help, and I read that as "no
   lowering exists". Both lowerings exist. See the resolution section.
   Adding
   `if slCastDrop and (Syms[idx].TypeKind = tyPointer) then slIsArrTarget := True`
   changes the message to `SetLength expects an ARRAY variable in IR codegen`.
   Neither classification has a lowering for a string held in a pointer slot —
   so this is an `ir.inc` piece of work and not a classifier line. The probe was
   reverted; the binary sha returned to `b8985660920b`, byte-identical, which is
   the control that says nothing else moved with it.

## The sibling count — NOT NEEDED, and the prediction that produced it was wrong

**CORRECTED 2026-09-06: the fix touches no backend arm at all.** Kept below
because the counting discipline is right even when the premise it served was
not — but this ticket's own `ir.inc`-with-five-twins prediction was mistaken, and
the refusal it reasoned from was a message about a MISSING TYPE MARK wearing the
shape of a message about a missing lowering.

## The sibling count, because a native green would mean nothing without it

The refusal has **five per-target twins**, each with the same message under a
target prefix — `ir_codegen386.inc:3284`, `ir_codegen_aarch64.inc:3246`,
`ir_codegen_arm32.inc:2613`, `ir_codegen_riscv32.inc:2906`,
`ir_codegen_xtensa.inc:3013`. A fix keyed on the x86-64 arm passes a native gate
and leaves four targets refusing. (Counted by frankH in the parent ticket; line
numbers not re-verified here, so check them before citing.)

The neighbouring `p^`-where-the-pointee-is-a-managed-string arm
(`bug-a-setlength-on-a-captured-managed-string-is-refused`) is the model: it
routes to the address-based `IR_SETLEN_STR`, which `defs.inc` documents as
reaching a target through *any* lvalue. A cast-tagged pointer slot is plausibly
the next shape past it, and that is a hypothesis, not a measurement.

## What a fix has to satisfy

1. `SetLength(AnsiString(p), 2)` compiles and yields `ab`.
2. The alias spelling `SetLength(t(p), 2)` does the same — it must, since the
   cast is dropped before either reaches the classifier.
3. Every existing `SetLength` target shape keeps its current classification; the
   `AN_INDEX` and `AN_FIELD` arms above carry two live tests
   (`test_field_rooted_nested_dyn_frozen_index`, `test_string_n_container_strides`)
   that caught a previous widening within the hour.
4. Whatever arm is added, exercise it on **one non-x86-64 target**, or the green
   is about one of six backends.


## RESOLVED 2026-09-06 — and my own prediction in this ticket was WRONG in a useful way

**I predicted `ir.inc`, with five per-target twins.** The fix is entirely in the
frontend: two guards in `pasparser_stmt.inc` and one case label in `ir.inc`'s
`NodeIsManagedString`, which is target-independent. **Zero backend arms.** The
prediction named a place and a count, so it could be wrong out loud, and it was.

What made it wrong: I read the refusal (`SetLength expects a string variable in
IR codegen`) as evidence that the LOWERING was missing. It was not. The target
arrived at codegen as `load_sym, tk=17` — **the pointer's VALUE, correctly
lowered, carrying no evidence that it addressed a string.** The machinery was all
there; the parser had thrown away the fact that would have routed it.

### The instrument that settled it was the DIAGNOSTIC, and it is the transferable half

Three candidate fixes produced that message **byte for byte**: retagging
`ASTTk`, keeping an `AN_PTR_CAST` node, and normalising to an `AN_DEREF`. A
message that is identical across three different wrong answers discriminates
nothing, so each attempt had to be reasoned about instead of read — and the
reasoning was wrong three times.

Making the refusal name the shape it refused (`IROpName(IRKind[val1Node])` and
the node's tk) turned the fourth attempt into a lookup: `load_sym, tk=17` says
the value is right and the type is unmarked; then `tk=23` after adding the cast
node says the mark arrived and the classifier is what is refusing. **Two
measurements, both free, after three failed inferences.** That change is kept.

### The pair, and neither half works alone

1. `pasparser_stmt.inc` — the SetLength cast-drop keeps the cast **as a node**
   when the target is a `Pointer` slot and the cast is to a MANAGED string.
   Dropping is right for a string variable and destroys the only evidence for a
   pointer.
2. …and classifies that target as the managed (-102) arm, because its symbol is
   neither an array nor a string.
3. `ir.inc` — `NodeIsManagedString` gains `AN_PTR_CAST` beside `AN_INDEX` and
   `AN_DEREF`. `IRLowerAddress` of the cast yields the OPERAND's slot, which is
   exactly the address `IR_SETLEN_STR` wants.

With only (1) the target reached the FROZEN -101 arm; with only (2) it reached
-102's symbol path and answered `SetLength expects an ARRAY variable`. **Two
different refusals for one missing pair**, which is why either half alone reads
as a dead end.

### `ASTTk` is not what the lowering reads — the same lesson, twice in one session

Retagging the node in place changed nothing here, exactly as it changed nothing
for the rvalue half of the parent ticket an hour earlier. The **cast node** is
what carries the fact.

### A row had to be dropped, and it is now its own ticket

Row F originally wrote the new characters after a grow. `t(r)[3] := 'c'` stores
nowhere, `t(r)[2]` reads a blank character where fpc reads `b`, and
`AnsiString(r)[3] := 'X'` does not parse at all — three observables, filed as
[[bug-p-indexing-a-string-cast-of-a-pointer-slot-reads-blank-and-stores-nowhere]].
Row F now asserts `Length` = 5 and `Copy(t(r),1,2)` = `ab`, which is what proves
the reallocated handle was written back into the slot: through a stale handle
`Length` answers 2.

### Positive controls, both still refusing

`SetLength(TI(i), 5)` for `TI = Integer` and `SetLength(Integer(p), 5)` are both
still errors. The first has an existing test behind it
(`a-flag-whose-default-is-a-real-answer-cannot-say-not-applicable`), and the
guard here is `slCastTk = tyAnsiString`, so an ordinal or frozen cast never
reaches the new path.
