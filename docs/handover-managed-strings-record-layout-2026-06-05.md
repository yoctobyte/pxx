# Handover: managed-strings self-compile — record-layout flip (F2)

**Date:** 2026-06-05. **For:** the next agent (sis AI). **Read with:**
`docs/plan-refcounted-compiler-strings.md` (the live plan; §F2 has the full
detail and the corrected approach).

## Goal

Make the compiler self-compile with refcounted (managed) `AnsiString`:
`pascal26 -dPXX_MANAGED_STRING compiler/compiler.pas` must produce a *correct*
compiler binary, then reach byte-identical fixedpoint. Payoff: BSS collapses
(already 1.6 GB → 213 MB from standalone-var handles; the rest is record arrays).

## What is DONE (this session — all committed, gate-clean)

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
- Tests: `test/test_managed_setlength_var.pas` wired into `make test`.
- Commits: `e5cafc7`, `da28c88`, `36ff5c8`, plan docs `6e1c4cf` + this handover.

State: the managed self-compile **runs to completion** and emits a binary; that
binary crashes only at F2 (below). Everything before F2 works.

## The ONE remaining blocker: F2

The managed compiler crashes in `AddConst` on `Syms[x].Name := name` — a
`rep movsb` of `[len][data]` from an 8-byte managed handle with a garbage length.

**Root cause (fully pinned):** `symtab.inc` ~389 (`IsRecordType`) maps ~15
built-in type names to hardcoded record ids. For those ids,
`RecSize` (425) / `RecFieldOffset` (446) / `RecFieldType` (568) are **hardcoded
to the frozen layout** (e.g. `RecFieldType(REC_TSYMBOL,'Name') = tyString`, `Name`
264 B inline @0, size 360). User records take the dynamic `UFld*`/`UClsSize_` path
and already lay a `tyAnsiString` field out as an 8-byte handle and work under
managed (verified). So **only the hardcoded built-in records are frozen**, and a
managed-handle store into their inline string field mismatches.

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

## The agreed fix (architect's call): computed engine, not hand-flipped offsets

Branch on the **target** define at **runtime** (`PasDefineExists('PXX_MANAGED_STRING')`),
NOT `{$ifdef}` — the same binary compiles frozen or managed targets, and the
parser already picks `tyAnsiString` vs `tyString` at runtime (parser.inc 2184,
4097); the layout functions must agree with that.

1. **Codegen first (all records, no reseed, byte-identical).** Fix managed
   `IR_FIELD` field gaps, mirroring F1 but for fields. Confirmed bug:
   `Length(rec.field)` on a managed-string field returns 0 (repro `/tmp/r1.pas`:
   `name=[hello] kind=7 len=0`). Deref the field slot before `[-8]`. Audit
   `rec.field[i]` r/w, `recA.field := recB.field`, passing `rec.field` as arg.
   Built-in arrays are globals (live forever) → no field finalization needed.
   Land + test on **user** records first.
2. **Replace the four hardcoded `Rec*` if-chains with one computed pass** driven
   by a per-record field table (field name + kind, declaration order, transcribed
   from defs.inc). ABI rule: scalar → 8; string →
   `PasDefineExists('PXX_MANAGED_STRING') ? 8 : 264` (this one line IS the flip);
   record → `RecSize`; array → `elem × count`. `TProc.Params: array[0..15] of
   TParam` (= 16 × `RecSize(REC_TPARAM)`, `BodyAddr@5024`, size 5056) is the
   gnarly nested-record-array case.
3. **Validation gate (do this before any managed step):** assert the **frozen**
   computed layout equals the current hardcoded constants (TSymbol=360, every
   offset). Match ⇒ engine reproduces the known-good ABI. Keep frozen
   `bootstrap`/`test`/`fpc-check` green here.
4. **FPC reseed `-dPXX_MANAGED_STRING`**, drive the tail past `AddConst` to a
   working `hello.pas`, then fixedpoint, then reconcile `fpc-check` (two managed
   runtimes; emitted code must match). Frozen default untouched (the `?8:264`
   returns 264 with no `-d`).

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
/tmp/p26managed test/hello.pas /tmp/hello_m && /tmp/hello_m          # does the managed compiler work?
# crash PC: gdb -q -batch -ex 'set debuginfod enabled off' -ex run -ex 'info registers rip rax rcx' --args /tmp/p26managed test/hello.pas /tmp/hello_m
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
