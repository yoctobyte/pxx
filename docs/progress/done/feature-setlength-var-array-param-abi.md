# `SetLength` on a `var` dynamic-array parameter (cross-cutting ABI)

- **Type:** feature
- **Status:** done
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

## Decision (LOCKED 2026-06-19) — mirror FPC: split the two param forms by declaration

The two array-param "kinds" are **not** polymorphic over each other and must be
distinguished at the *declaration*, exactly as FPC does. No monomorphization, no
static→dynamic jacket, no up/down-typing, no copy.

| Declaration form | Kind | ABI (the slot holds) | Resizable (`SetLength`) | Accepts |
|---|---|---|---|---|
| `array of T` (literal in the param list) | **open array** | borrowed **data pointer** (+ high, when wired) | **no** — hard error (matches FPC) | static array, dynamic array, or single element |
| named `TDynArr = array of T` | **dynamic-array param** | by value: the **handle**; by `var`/`out`: **`&caller_slot`** | **yes** | only a dynamic array of `TDynArr` |

Why this dodges every trap (recorded so we don't relitigate):
- **No jacket / no overhead** — open arrays keep borrowing the data pointer;
  fixed-memory apps unaffected. The open-array path is left untouched.
- **No double-compile / no coroutine sabotage** — each form has exactly one ABI;
  nothing monomorphizes, so the stackless/spawn transform still sees one body.
- **No up/down-type + copy** — the resizable form accepts *only* a matching
  dynamic-array handle; a static array passed to a `var TDynArr` param is a
  **type mismatch rejected at the call** (as in FPC), so no conversion ever runs.
- **No "chicken error on mixed types"** — splitting by declaration removes the
  ambiguity that would have forced it.

The resizable form reuses the **managed-`AnsiString`-var-param machinery** as its
template (the slot holds `&caller_slot`; the read path derefs once — see the
`IR_LEA` write-mode special case in `ir_codegen.inc` and
`test_managed_setlength_var`).

## Implementation plan (4 targets; mechanical, but real — do in a clean session)

Pre-flight: confirm `compiler.pas` passes **no** named dynamic-array type by
`var`/`out` (grep the param decls). If true, the self-host fixedpoint cannot
regress from this change; if false, those call sites convert to the new ABI and
must be re-validated. (Open-array `array of T` params in `compiler.pas` are
unaffected — their path does not change.)

1. **Parser — classify (the foundational fix).** In the named-array-type param
   branch (`parser.inc` ~7621), when `ArrTypeIsDyn[paramAi]`, mark the param a
   true dynamic array: set its symbol `ArrLen = -1` (and `SymDynDepth`/element
   type) instead of letting `AllocParam` stamp the open-array `ArrLen = 1000`.
   The `SetLength` classifier (`parser.inc` ~5584) then routes it to `-102`
   automatically. Open `array of T` literal params stay `ArrLen = 1000`.
2. **Call site — pass `&caller_slot`.** For a `var`/`out` param whose type is a
   named dynamic array, the IR call-arg lowering must pass the **address of the
   caller's slot** (not the borrowed data pointer). For a *by-value* dynamic-array
   param, pass the handle (current behaviour is fine). Mirror how managed
   `AnsiString` var args are already lowered.
3. **Read paths — one extra deref for the by-ref dynarray param.** Thread the
   `IsRef`-param deref (slot → caller_slot → handle) through `Length`, indexing,
   and element load/store, on **all four** backends — copy the shape of the
   existing managed-`AnsiString`-var `IR_LEA` read/write gate
   (`ir_codegen.inc:1661-1679` and the three cross equivalents).
4. **`SetLength` (`-102`).** The x86-64 `IsRef` branch (`ir_codegen.inc:3066`)
   already assumes `&caller_slot` — once (2) actually passes that, it works.
   Replace the cross backends' `not yet supported` guards with the
   `&caller_slot` deref + `PXXDynSetLen(slotAddr, n, desc)` call (the speculative
   cross edits written + reverted on 2026-06-19 are the right shape; re-derive
   them against the corrected ABI).
5. **Open-array `SetLength` stays a hard error** on all four targets (you cannot
   `SetLength` an open array — FPC errors too). Make the message say "declare the
   param as a named dynamic-array type to resize it."

## Acceptance

`SetLength(a, n)` inside `procedure P(var a: TDynArr)` resizes the caller's array
and preserves `min(old,new)` elements (grow / shrink / zero), with `Length` and
indexing consistent, on all four hosted targets — output-equal to a reference
(`test_cross_setlen_varparam`, int + AnsiString element types) and byte-identical
self-host + `cross-bootstrap` preserved. `SetLength` on an `array of T` open-array
param errors cleanly on all four.

## Log
- 2026-06-19 — opened; root-caused both the misclassification and the ABI
  contradiction. No code changed (a speculative cross port was written, then
  reverted once the x86-64 path was found equally broken).
- 2026-06-19 — **design LOCKED** (with the user): mirror FPC by splitting the
  two param forms by declaration (open array = non-resizable fat ptr; named
  dynamic-array type = resizable by-ref-handle ABI). No monomorphization / jacket
  / copy. Wrote the 5-step implementation plan above. Ready to implement in a
  clean session; status stays backlog until then.
- 2026-06-19 — **DONE**, all 5 steps, byte-identical on all four hosted targets.
  Pre-flight confirmed `compiler.pas` declares no named dynamic-array param
  (no self-host regression risk). Implementation:
  1. Parser (`parser.inc` ~7621): named-array param branch now reads
     `ArrTypeIsDyn`/`ArrTypeDynDepth` into a new per-param `pDynDepth`; the alloc
     loop stamps `ArrLen = -1` + `SymDynDepth` (and persists the depth in a new
     `ProcParamDynDepth[pi*16+j]` array, since param syms are reused across procs).
     Open `array of T` literal params stay `ArrLen = 1000`. `SetLength` classifier
     (`parser.inc` ~5584) now hard-errors on a non-dynamic array target
     ("declare the parameter as a named dynamic-array type to resize it").
  2. Call site (`ir.inc` `IRLowerCallArg`): a by-ref arg whose target param has
     `ProcParamDynDepth>0` is passed via `IR_SLOTADDR` (= &caller_slot), not the
     `IRLowerAddress`→IR_LEA handle value. A forwarded by-ref param takes the
     normal address path.
  3. Read paths — one extra deref for the by-ref dynarray param, per backend:
     - x86-64 (`ir_codegen.inc` IR_LEA): write mode → `&caller_slot` (one load,
       for COW/SetLength); read mode → data ptr (second load).
     - i386 / arm32: no COW; IR_LEA always loads to the data ptr (two loads for
       by-ref). SetLength reads the frame slot directly, then one extra load to
       reach `&caller_slot`.
     - aarch64: `EmitLoadVarAddrA64` already bakes the by-ref deref (yields
       `&caller_slot`), so the existing single ldr already reaches the data ptr —
       no extra deref, and SetLength uses `&caller_slot` as-is. (Initial port
       over-derefed here; fixed.)
  4. `SetLength` (-102): x86-64 IsRef branch already published to `&caller_slot`;
     i386/aarch64/arm32 `not yet supported` guards replaced with the
     `&caller_slot` deref + existing `PXXDynSetLen(slotAddr, n, desc)` call.
  5. Open-array `SetLength` is a clean hard error on all four.
  Acceptance met: `test_cross_setlen_varparam` (int + AnsiString element types,
  grow/shrink/zero) output-equal to FPC on all four hosted targets; wired into
  test-core + the i386/aarch64/arm32 cross suites. `make test` byte-identical
  fixedpoint + `--threadsafe`; `make cross-bootstrap` byte-identical on all 3.
  Landed in commit 15a70de.
