# SetLength on a named dyn-array-alias class/record field misrouted to string path

- **Type:** bug (compiler / codegen) — **Track A**
- **Status:** **DONE** — fixed `4a37b00`, re-pinned v35.
- **Severity:** blocked Track B (`lib/rtl/vm.pas` "blocked on codegen bug").
- **Opened / Closed:** 2026-06-22
- **Found by:** Track B (bytecode VM library, commit `56678e2`).

## Symptom

```
pascal26:NNN: error: SetLength expects a string variable in IR codegen
```
Compiling `examples/vm/vmdemo.pas` (uses `lib/rtl/vm.pas`, whose `TMachine`
class has `FOps, FArgs: TIntArray` and `FLabelName: array of AnsiString`
fields). Any `SetLength(Self.FOps, n)` failed.

## Root cause

A class/record field declared with a **named** dynamic-array type alias
(`TIntArray = array of Integer`) was parsed by the named-type *else* branch of
the field type parser (`ParseTypeSection`), which only did `fTk := ParseTypeKind`
and never set `fIsDyn` / `fDynDepth`. So the field recorded `UFldDynDepth = 0`
and `UFldIsArray = False`. At the SetLength call site the `AN_FIELD` dyn-array
classifier (`RecFieldDynDepth(...) > 0`) then read 0 and routed the call to the
**string** SetLength path (specialId 101), whose codegen requires an `IR_LEA`
string lvalue → the error.

Inline `array of T` fields worked (that branch *does* set the flags); only the
**named-alias** field was broken, and for **both** int and string element types
(not a string-specific bug — the earlier narrowing that pointed at AnsiString was
a red herring from a two-field test).

## Fix

In both the class- and record-field type-parse else branches, detect a named
array-type alias via `FindArrayType`, and when `ArrTypeIsDyn` set
`fIsDyn`/`fDynDepth` + element `fTk`/`fRec` from the alias — mirroring the
existing named-dynamic-array **param** path (`parser.inc` ~9549). `Length`,
indexing and `SetLength` on the field now all work.

## Verification

- `examples/vm/vmdemo.pas` → `ALL OK` (loopsum 55, fact 120/120, subr 36/81,
  bad mnemonic rejected).
- Regression `test/test_named_dynarray_field.pas` (class int+string fields +
  record field; SetLength/index/Length) in `make test-core`.
- `make test` + fpc-check byte-identical; cross-bootstrap (i386/aarch64/arm32)
  byte-identical self-fixedpoint. `make lib-test` green. Re-pinned **v35**.

## Log
- 2026-06-22 — Filed + fixed (Track A). Named dyn-array alias fields now carry
  their dyn-array depth; SetLength routes correctly. Unblocks the VM library.
