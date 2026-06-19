# `SetLength` on a `var` dynamic-array parameter (cross-cutting ABI)

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-19 (spun out of feature-cross-target-feature-parity — the
  matrix had this mislabelled as "x86-64 ✓ / cross ✗"; investigation showed it
  is broken on **all four** targets, so it is a general feature gap, not a cross
  port)

## Summary

`SetLength` on a dynamic array passed by reference (`procedure P(var a: TArr)`
where `TArr = array of T`) does **not** resize the caller's array on any target,
including x86-64. The earlier parity matrix marked x86-64 ✓ purely because the
x86-64 backend has *code* for the case (the `-102` `IsRef` branch in
`ir_codegen.inc`) while the cross backends carry an explicit
`Error('… SetLength on a var-array parameter not yet supported')`. Neither path
was ever behaviourally tested. A minimal probe:

```pascal
type TIntArr = array of Integer;
procedure GrowI(var a: TIntArr; n: Integer); begin SetLength(a, n); end;
var a: TIntArr;
begin GrowI(a, 4); writeln(Length(a)); end.   { prints 0, then SIGSEGV on x86-64 }
```

## Root cause (the real, cross-cutting issue)

Two independent problems, the second structural:

1. **Misclassification (parser).** `AllocParam` (`symtab.inc`) sets every array
   parameter's `ArrLen := 1000` (the open-array marker), never `-1`. The
   `SetLength` classifier in `parser.inc` routes to the dynamic-array path
   (`-102`) only when `Syms[idx].IsArray and (Syms[idx].ArrLen = -1)`, so a
   `var` dynamic-array param falls through to the **string** path (`-101`) and is
   miscompiled. The named-array-type param branch (`parser.inc` ~7621) knows the
   type is dynamic (`ArrTypeIsDyn[paramAi]`) but discards that fact.

2. **Contradictory ABI (the hard part).** Even if classified correctly, the two
   relevant conventions disagree:
   - **How the argument is passed:** `ParseCallArg` / the IR call-arg lowering
     pass a by-ref *or* array param as the **open-array data pointer** (the
     borrowed heap block). This is why `Length(a)` and indexing already work on a
     `var` dynamic-array param (verified: a fill-through-var test reads/writes the
     caller's elements correctly on x86-64).
   - **What `SetLength` needs:** to *resize and publish a new handle back to the
     caller*, the callee needs the **address of the caller's array slot**
     (`&caller_slot`), not the data pointer. The x86-64 `-102` `IsRef` branch is
     written assuming `&caller_slot` (it does `mov rsi,[rbp+off]` then
     `mov rsi,[rsi]`), which is simply not what the call site passes → garbage.

   These two cannot both hold for the same single pointer slot. Managed
   `AnsiString` var params already resolve this by using the **by-ref-handle
   ABI** consistently (the slot holds `&caller_slot`; the read path derefs once —
   see the `IR_LEA` write-mode special case in `ir_codegen.inc` and
   `test_managed_setlength_var`). Dynamic arrays would need the *same* treatment:
   mark such params `ArrLen = -1`, pass `&caller_slot` at every call site, and
   thread the extra deref through `Length` / indexing / read / `SetLength` on
   **all four targets**.

## Why it is a backlog item, not a quick fix

It is a from-scratch ABI decision with breadth across every array operation and
every backend, plus self-host risk (whether `compiler.pas` uses any
`var <named-dynarray>` params must be checked before flipping the param ABI).
It is **not** a localized cross port, so it was deliberately *not* guessed at
during the cross-parity close-out. FPC's behaviour (a `var` dynamic-array param
*is* resizable and publishes back) is the target semantics.

## Decision needed

Adopt the managed-string by-ref-handle ABI for `var`/`out` dynamic-array params
(mark `ArrLen = -1`; pass `&caller_slot`; add the read-path deref everywhere)?
This is the FPC-correct model but touches Length/index/store/SetLength on all
four targets. Until decided, the cross backends keep the explicit
`not yet supported` guard and x86-64 keeps its (also non-functional) `-102`
`IsRef` branch — i.e. the feature is uniformly absent, which is at least honest.

## Acceptance

`SetLength(a, n)` inside `procedure P(var a: TArr)` resizes the caller's array
and preserves `min(old,new)` elements (grow/shrink/zero), with `Length` and
indexing consistent, on all four hosted targets — verified output-equal to a
reference and byte-identical self-host preserved.

## Log
- 2026-06-19 — opened; root-caused both the misclassification and the ABI
  contradiction (see above). No code changed (a speculative cross port was
  written, then reverted once the x86-64 path was found equally broken).
