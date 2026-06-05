# Handover: managed-strings self-compile — fixedpoint reached after F2

**Date:** 2026-06-05. **For:** the next agent (sis AI). **Read with:**
`docs/plan-refcounted-compiler-strings.md` (the live plan; §F2 records the
completed computed-layout refactor and the fixedpoint tail).

## Goal

Make the compiler self-compile with refcounted (managed) `AnsiString`:
`pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas` must produce a *correct*
compiler binary, then reach byte-identical fixedpoint. Payoff: BSS collapses
(already 1.6 GB → 213 MB from standalone-var handles; the rest is record arrays).

## What is DONE (all committed, gate-clean)

Drove the managed self-compile from first-error to the last wall. Every fix is
`tyAnsiString`/`IsRef`-gated, so the **frozen** default build stays byte-identical
(`make bootstrap` / `test` / `test-nilpy` / `fpc-check` all green; the frozen
compiler binary grew only because it carries the new source, output is identical).

- Gap A managed builtins: `LoadFile` (new runtime helper `AnsiStrLoadFile` =
  open/lseek-size/alloc/read/nul-term + publish), `SysOpen` (accept handle),
  `ParamStr`/`ArgStr` (`EmitArgvToStringManaged`). `SYS_LSEEK` added.
  `MAX_CODE` 1 MB → 4 MB (managed code is ~1.06 MB).
- Gap B: `SetLength` and `s[i] := c` through a `var` managed string (IsRef
  forwarded-slot addressing on the write side).
- F1: by-ref managed-string **read** addressing — `Length(var s)` and index-read
  now deref the forwarded slot to the handle (the fix is at the two consumers —
  `tkLength` branch and `IR_INDEX` read — not the `IR_LEA` node, so forwarding a
  var-param keeps working).
- F1-adjacent user-record field read: `Length(rec.field)` now derefs the managed
  string field slot before reading the length word. Regression:
  `test/test_managed_record_field_string_ops.pas`.
- F2: built-in compiler records now use computed metadata-driven target layouts
  instead of hardcoded frozen `RecSize`/`RecFieldOffset`/`RecFieldType` chains.
  The string field size/type branch uses runtime
  `PasDefineExists('PXX_MANAGED_STRING')`, not `{$ifdef}`. Frozen layout is
  validated against the old constants before codegen.
- Tests: `test/test_managed_setlength_var.pas` and
  `test/test_managed_record_field_string_ops.pas` wired into `make test`.
- Stage-2 managed self-compile growth: fixed by making scalar managed-string
  `SetLength` byte-sized even through `var AnsiString`, resizing unique buffers
  in place when allocator capacity permits, allocating geometric headroom for
  growth, and guarding parser method metadata reads without relying on
  short-circuit `and`. Regression: `test/test_managed_setlength_growth.pas`.
- Commits: `e5cafc7`, `da28c88`, `36ff5c8`, `1640750`, `9039a27`, `2f82301`; plan docs
  `6e1c4cf`, `e2029d3`.

State: the F2/AddConst crash is gone, and the stage-2 growth blocker is gone.
The frozen self-hosted compiler can compile `compiler/compiler.pas
-dPXX_MANAGED_STRING` into a managed compiler; that managed compiler can
compile itself again with `-dPXX_MANAGED_STRING`; stage1 and stage2 compare
byte-identical; the managed compiler also compiles and runs `test/hello.pas`.

## Current state: managed fixedpoint

Latest probe:

```
./compiler/pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas /tmp/p26_managed_check_1
/tmp/p26_managed_check_1 -dPXX_MANAGED_STRING compiler/compiler.pas /tmp/p26_managed_check_2
cmp /tmp/p26_managed_check_1 /tmp/p26_managed_check_2
/tmp/p26_managed_check_2 test/hello.pas /tmp/hello_managed_check
/tmp/hello_managed_check
```

Observed:

- `/tmp/p26_managed_check_1` builds successfully (`code=1094860B data=30600B
  bss=106035320B procs=485`).
- `/tmp/p26_managed_check_2` builds successfully with the same sizes.
- `cmp` reports stage1 == stage2.
- The stage2 managed compiler builds `test/hello.pas`, which prints
  `Hello, World!`.

The normal frozen gate is also clean after this fix:
`make bootstrap && make test && make test-nilpy && make fpc-check`, followed by
`make symbols`.

No current correctness blocker is known on the managed self-compile path. The
next work is policy/operational: decide whether to record a deliberate managed
reseed/stable artifact, add a first-class managed fixedpoint make target if
desired, and then continue any remaining managed-string cleanup outside the
self-compile critical path.

## F2 record-layout fix: delivered summary

The old crash was:

`Syms[x].Name := name` in `AddConst` stored an 8-byte managed handle into a
target `TSymbol.Name` field that the built-in record tables still described as a
264-byte frozen inline string.

**Root cause (verified):** `RecSize`/`RecFieldOffset`/`RecFieldType` are
target-codegen metadata only. They never access the compiler's own FPC/self-host
struct memory. The old built-in tables encoded a target ABI of "every scalar =
8 bytes; frozen string = 264 bytes", while user records already selected
`tyAnsiString` handle fields under `-dPXX_MANAGED_STRING`.

Records to fix (string-bearing built-ins): `TToken(SVal)`, `TStrEntry(Text)`,
`TSymbol(Name)`, `TParam(Name)`, `TProc(Name + Params: array of TParam)`,
`TTemplate(Name,Param)`, `TSpecialization(Name,TemplateName,ConcreteName)`,
`TGenericFunc(Name,Param)`, `TPendingGFSpec(ConcreteName,SpecName)`.

## Two facts that shape the fix (verified — do not re-derive)

1. `RecSize`/`RecFieldOffset`/`RecFieldType` are used **only for target codegen**
   (sizing/addressing records in the program being compiled). They are **never**
   used to access the compiler's own `Syms`/`Procs` memory. So they are a
   self-consistent *target record ABI* — free to change, must stay internally
   consistent + stable across self-host stages.
2. That ABI is **"every scalar = 8 bytes"** (TSymbol Integer/Boolean/enum all 8
   apart, string = 264), which is NOT FPC's packing and NOT the user-record rule
   (`parser.inc` ~4716 packs via `TypeSize`: Integer=4, Boolean=1). So you cannot
   route built-ins through the user-record engine.

Delivered approach:

- `compiler/symtab.inc` now has per-record field metadata helpers
  (`BuiltinRecField*`) and computes size/offset/type/array/record-id from one
  declaration-order table.
- String field size/type is runtime target-state:
  `PasDefineExists('PXX_MANAGED_STRING') ? tyAnsiString/8 : tyString/264`.
- `TProc.Params` is handled as a nested record array:
  `16 * RecSize(REC_TPARAM)`.
- `TMethodFixup` preserves its old 4-byte scalar fields (`DataPos@0`,
  `ProcIdx@4`, size 8).
- `ValidateBuiltinRecordLayout` asserts the frozen computed layout equals the
  old hardcoded constants before codegen; skipped for managed targets.

## Previous agreed fix notes (kept for context)

Branch on the **target** define at **runtime** (`PasDefineExists('PXX_MANAGED_STRING')`),
NOT `{$ifdef}` — the same binary compiles frozen or managed targets, and the
parser already picks `tyAnsiString` vs `tyString` at runtime (parser.inc 2184,
4097); the layout functions must agree with that.

1. **DONE — codegen first (all records, no reseed, byte-identical).** Fix managed
   `IR_FIELD` field gaps, mirroring F1 but for fields. Confirmed bug:
   `Length(rec.field)` on a managed-string field returns 0 (repro `/tmp/r1.pas`:
   `name=[hello] kind=7 len=0`). Deref the field slot before `[-8]`. Audit
   `rec.field[i]` r/w, `recA.field := recB.field`, passing `rec.field` as arg.
   Built-in arrays are globals (live forever) → no field finalization needed.
   Land + test on **user** records first.
2. **DONE — replace the four hardcoded `Rec*` if-chains with one computed pass** driven
   by a per-record field table (field name + kind, declaration order, transcribed
   from defs.inc). ABI rule: scalar → 8; string →
   `PasDefineExists('PXX_MANAGED_STRING') ? 8 : 264` (this one line IS the flip);
   record → `RecSize`; array → `elem × count`. `TProc.Params: array[0..15] of
   TParam` (= 16 × `RecSize(REC_TPARAM)`, `BodyAddr@5024`, size 5056) is the
   gnarly nested-record-array case.
3. **DONE — validation gate:** assert the **frozen**
   computed layout equals the current hardcoded constants (TSymbol=360, every
   offset). Match ⇒ engine reproduces the known-good ABI. Keep frozen
   `bootstrap`/`test`/`fpc-check` green here.
4. **DONE — managed fixedpoint.** The tail is past `AddConst`; the managed
   compiler can compile/run `hello.pas`; managed stage1 and stage2 are
   byte-identical. Frozen default remains untouched (the `?8:264` returns 264
   with no `-d`). Next: decide how to package/record the managed reseed and
   whether to add an automated managed fixedpoint gate.

## Key file:line

- `compiler/defs.inc` record decls: `TToken`@262 `TStrEntry`@277 `TSymbol`@329
  `TParam`@345 `TProc`@353 `TTemplate`@376 `TSpecialization`@383
  `TGenericFunc`@390 `TPendingGFSpec`@407. `MAX_CODE`@4. `SYS_LSEEK`@~199.
- `compiler/symtab.inc`: `REC_*` consts @370-383; `IsRecordType` (name→id)@386;
  `RecSize`@425; `RecFieldOffset`@446; `RecFieldType`@568; `RecFieldRecId`@630;
  `TypeSize`@728. (Line numbers drift — `make symbols` / verify before editing.)
- `compiler/ir_codegen.inc`: managed string runtime + `EmitAnsiStrLoadFile` /
  `EmitLoadFileManaged` / `EmitArgvToStringManaged` / `EmitPublishManagedString`
  near `EmitAnsiStringRuntime`; `tkLength` managed branch (~2951); `IR_INDEX`
  (~1812); `IR_LEA` (~1721); SetLength `specialId=102` (~3100).
- `compiler/parser.inc`: `SysOpen` accept (~1985); managed ArgStr store
  special-case (~1593 in the `IR_STORE_SYM tyAnsiString` branch).

## How to drive / probe

```
fpc -O2 -Tlinux -Px86_64 -o/tmp/p26new compiler/compiler.pas        # build from source
/tmp/p26new -dPXX_MANAGED_STRING compiler/compiler.pas /tmp/p26managed   # self-compile (managed)
/tmp/p26managed test/hello.pas /tmp/hello_m && /tmp/hello_m          # should print Hello, World!
/tmp/p26managed -dPXX_MANAGED_STRING compiler/compiler.pas /tmp/p26managed2  # current growth blocker
# map a crash vaddr to a proc: dump proc list from the self-compile (proc N: NAME at OFFSET), vaddr ≈ 0x400000 + codeoffset (verify against objdump)
```
Frozen gate after any compiler edit: `make bootstrap && make test && make
test-nilpy && make fpc-check` (all must stay byte-identical).

## Landmines

- The frozen path must stay byte-identical at every commit until the deliberate
  reseed in step 4. Gate every managed change on `tyAnsiString` / runtime
  `PasDefineExists`.
- Don't hand-edit `RecFieldOffset` per record — build the engine + validation
  instead (that's the whole point; otherwise you re-create the landmine).
- `MAX_UFIELD` / `TParam` field-pool: untouched — built-ins aren't UClasses.
- Parked, out of scope: named-dynarray-alias `SetLength` misroute
  (plan doc §F note), the F2-adjacent right-sizing idea (memory:
  `project_managed-string-f2-direction`).
