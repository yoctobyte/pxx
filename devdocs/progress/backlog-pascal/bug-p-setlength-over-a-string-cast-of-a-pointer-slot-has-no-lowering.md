---
slug: bug-p-setlength-over-a-string-cast-of-a-pointer-slot-has-no-lowering
title: "SetLength through a string cast of a Pointer slot has no lowering, in EITHER spelling"
track: P
prio: 45
type: bug
status: backlog
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "`var p: Pointer; AnsiString(p) := 'abc'; SetLength(AnsiString(p), 2)` is refused with `SetLength expects a string variable in IR codegen`; fpc 3.2.2 -Mdelphi accepts it and prints `ab`. SPLIT OUT OF bug-p-a-string-alias-cast-over-a-pointer-slot-is-a-no-op-and-reads-the-pointer, which bundled it as requirement 2 -- and it is NOT an alias defect: measured, the ALIAS spelling `SetLength(t(p), 2)` and the BUILT-IN spelling fail identically, so the alias is not part of the cause. The parser drops the cast (pasparser_stmt.inc, slCastDrop) and hands the classifier a Pointer SYMBOL, which is neither an array nor a managed string, so the target is classed as a frozen string and codegen refuses. Forcing the other classification was tried and answers `SetLength expects an ARRAY variable` -- so neither arm has a lowering for a pointer-held string and this is an ir.inc job, with FIVE per-target twins of the refusal."
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
3. **Forcing the other arm does not help, and that is the finding.** Adding
   `if slCastDrop and (Syms[idx].TypeKind = tyPointer) then slIsArrTarget := True`
   changes the message to `SetLength expects an ARRAY variable in IR codegen`.
   Neither classification has a lowering for a string held in a pointer slot —
   so this is an `ir.inc` piece of work and not a classifier line. The probe was
   reverted; the binary sha returned to `b8985660920b`, byte-identical, which is
   the control that says nothing else moved with it.

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
