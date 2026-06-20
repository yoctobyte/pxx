# const record param with a managed (dynarray) field crashes by-ref on i386 + aarch64

- **Type:** bug (compiler / codegen, cross-target)
- **Status:** done
- **Owner:** track A
- **Opened:** 2026-06-19 (found while adding cross tests for
  bug-const-byref-record-param-temp)
- **Closed:** 2026-06-20

## Symptom

Passing a record that contains a **managed field** (e.g. `array of Int64`) to a
`const` record parameter (which is passed by reference) **segfaults at runtime
on i386 and aarch64**. arm32 and x86-64 are fine. This is independent of
temporaries — it crashes even for a plain named variable.

```pascal
type TR = record neg: Boolean; limbs: array of Int64; end;
function MakeR(a: Int64): TR;
begin SetLength(Result.limbs, 1); Result.limbs[0] := a; end;
function SumR(const r: TR): Int64;
begin SumR := r.limbs[0]; end;
var t: TR;
begin
  t := MakeR(7);
  Writeln(SumR(t));   { x86-64: 7 / arm32: 7 / i386: SIGSEGV / aarch64: SIGSEGV }
end.
```

Plain (unmanaged) record `const` params work on all four targets — only a
record carrying a managed field is affected.

## Likely area

The const-record-by-ref ABI on 32-bit / aarch64 when the record has managed
fields. Suspects from history: the fat/managed record param marshalling, the
`RecSize<=8` vs forced-by-ref decision per target (parser.inc ~8126), or the
managed-record copy/deref at the callee. Note `bug-const-byref-record-param-temp`
already confirmed the *temp materialization* path (`IRLowerCallArg` `needTemp`)
is correct on all targets for unmanaged records; this is the managed-field
read/marshal, not the temp.

## Repro

```
./compiler/pascal26 -dPXX_MANAGED_STRING --target=i386    /tmp/r.pas /tmp/r_i386
./compiler/pascal26 -dPXX_MANAGED_STRING --target=aarch64 /tmp/r.pas /tmp/r_a64
tools/run_target.sh i386    /tmp/r_i386     # SIGSEGV
tools/run_target.sh aarch64 /tmp/r_a64      # SIGSEGV
```

## Impact

Blocked managed-record value APIs (bignum `TBigInt`, JSON nodes, etc.) from
being exercised through `const` params on the 32-bit/aarch64 cross targets. The
x86-64 path (the self-host gate) was unaffected, so it did not block bootstrap.
Fixed in `1df5c76`; the managed-record variants are now back in the i386,
aarch64, and arm32 cross suites.

## Log
- 2026-06-19 — opened by track A. Found via the const-record-temp cross tests;
  isolated to the managed-field-by-ref read (named var crashes too, not just
  temporaries). i386 + aarch64 affected; arm32 + x86-64 fine.
- 2026-06-20 — fixed by preserving `ParseSubroutine`'s current-procedure index
  while emitting managed aggregate local zeroing. Stable default pinned to v14.

## Diagnosis (2026-06-19) — narrowed to the managed-record FUNCTION RETURN

The `const`-param framing was a red herring. The real trigger is **returning a
record with a managed (dynarray) field from a function** and then reading that
field. Minimal repro (no const param):

```pascal
type TR = record neg: Boolean; limbs: array of Int64; end;
function MakeR(a: Int64): TR;
begin Result.neg := True; SetLength(Result.limbs, 1); Result.limbs[0] := a; end;
var t: TR;
begin
  t := MakeR(7);
  { i386 + aarch64: t.neg = True survives, but Length(t.limbs) = 0 (nil handle);
    reading t.limbs[0] then segfaults. x86-64 + arm32: correct (len 1, value 7). }
end.
```

Narrowing:
- `t := a` (plain managed-record copy, both locals) WORKS on all four targets —
  so `IR_COPY_REC_MANAGED` is fine.
- A managed record built in place (no function) WORKS on all four.
- Only the **function-return** path fails, and only for the managed (handle)
  field: the non-managed field at offset 0 (`neg`) copies fine; the dynarray
  handle field is lost (Length 0 = nil), so it is a copy-RANGE / field-OFFSET
  problem in the aggregate return, not a refcount over-release (i386's epilogue
  cleanup loop does not even release managed-record locals).

The aggregate return (symtab.inc ~3448 i386 / ~3568 arm32, and the aarch64
equivalent) builds `Result` in a local record slot, then **raw-copies** it to the
caller's hidden destination by `RecSize(Result)` bytes and returns the dest
pointer. `SizeOf(TR)` per target: **i386 = 8, arm32 = 8, aarch64 = 16, x86-64 =
16**. Field offsets are target-aware (parser.inc ~7246, `TARGET_PTR_SIZE`): the
`limbs` handle sits at offset **4** on the 32-bit targets and **8** on the 64-bit
ones, so size and field offset are internally CONSISTENT on each target and the
`RecSize`-sized raw copy does span the handle field. (An earlier "i386 field
offset 8 vs size 8" guess is therefore WRONG — ruled out.)

Because the pass/fail split (i386 + aarch64) does NOT line up with the 32/64-bit
split, copy-size is not the cause and there are likely **two distinct root
causes**. The handle is lost specifically through the function-return path:
either `SetLength(Result.limbs)` in the callee does not write the handle into the
same slot the aggregate-return copy reads, or the return/epilogue drops it. Next
step: dump `MakeR`'s IR/asm on i386 and aarch64 and watch where
`SetLength(Result.limbs)` actually stores the handle vs where the aggregate
return raw-copies from; compare to the working x86-64 emit (which retains the
managed fields inline at `IR_COPY_REC_MANAGED`). Note also that the i386 epilogue
cleanup loop (symtab.inc ~3418) only releases AnsiString/interface locals, not
managed-record or dyn-array locals — a latent leak, and a sign the i386
managed-record return path is incomplete.

Both are independent of `Copy` and of the `const` param. x86-64 self-host is
unaffected. Repro: `SetLength(Result.limbs,1); ...; t := MakeR(7);
Writeln(Length(t.limbs))` — expect 1, get 0 on i386/aarch64.

## Further narrowing (2026-06-19, session 2)

Decisive: `SetLength(Result.limbs, 1)` works INSIDE the callee — adding a
`Writeln(Length(Result.limbs))` before the return prints 1 with the value
correct on both i386 and aarch64. The handle is only lost in the **aggregate
return copy** (Result local → caller's hidden dest, a `RecSize`-sized raw move at
symtab.inc ~3456 i386 / the aarch64 epilogue). So the dynarray handle field lives
at an offset the `RecSize`-sized copy does not span — i.e. the record's field
offset for the managed field and `RecSize` disagree for this layout (the field is
at/after `RecSize`). Confirm by disassembling the callee: compare the byte offset
SetLength writes the handle to against `RecSize` (the copy length) and the
caller's field-read offset; align the three. (`@r.limbs` to probe the offset from
user code is rejected — "undefined variable (NativeInt)" on the cast — so use a
disassembly or a non-managed proxy field.) This is independent of the now-fixed
hidden-temp nil-init (`bug-proc-local-managed-record-uninit`).

## Disassembly findings (2026-06-20, session 3) — old working theory

Disassembled i386 `MakeR` (a record-returning function). It builds `Result` in a
local (ebp-0x10), stores the handle into `Result.limbs` correctly — and then
**`leave; ret` with NO aggregate-return copy**. The Result is never written to the
caller's hidden destination (the dest pointer is saved at prologue to ebp-0x14 but
never read back). So the caller's `t := MakeR(...)` copies from an uninitialised
hidden-dest temp → `t.limbs` is nil → Length 0 → segfault on deref. (i386 field
offset for `limbs` = 4, RecSize = 8, so the copy WOULD span it — the copy is just
absent.)

The copy is absent because `EmitProcEpilog` (symtab.inc ~3448) receives
**`retSymIdx = -1`** for `MakeR` on i386, so the aggregate branch (3450, which
emits `mov edi,[dest]; lea esi,[Result]; rep movsb; mov eax,dest`) is skipped and
only `leave; ret` is emitted. On x86-64 the same proc gets `retSymIdx = 17`
(valid) and works.

`Procs[MakeR].RetSymIdx` is **17 at parse-set (parser.inc ~8351), 17 at the
prologue, 17 through `CompileAST` post-`IRLowerAST`, then -1 by the time the
epilog runs** — i.e. it is reset to -1 *during* `IREmitMachineCode` (i386), before
the epilogue. `ProcAggregateDestSym[MakeR]` stays valid (18) throughout. `MakeR`
is registered exactly once (no re-registration), and the only `RetSymIdx := -1`
is the proc-init at symtab.inc:2774 — which did NOT re-fire. So an UNIDENTIFIED
write resets `Procs[41].RetSymIdx` (Name stays "MakeR") during i386 emission.

Also unresolved: the `EmitProcEpilog` call that emits MakeR's bare `leave;ret` is
NOT `ir_codegen386.inc:3148` (the IR_TERMINATE handler — instrumented, did not
fire for MakeR) nor `parser.inc:9038` (instrumented, did not fire). Find the
actual caller. NEXT SESSION (fresh): (1) find what writes `Procs[*].RetSymIdx`
during i386 `IREmitMachineCode` — likely a stray field write via a wrong
proc/offset, or a lazy helper-proc registration that reuses the slot; (2) find the
real epilog call path for a record-returning proc on i386. The aarch64 variant is
separate (segfaults rather than nil) and needs its own pass. x86-64 self-host is
unaffected throughout.

## Resolution (2026-06-20)

The missing aggregate-return copy was real, but the `RetSymIdx` reset theory was
wrong. An FPC debug build showed `Procs[MakeBig].RetSymIdx` stayed valid through
codegen. At the final epilogue call, `CurProc` still pointed at the record-return
function and `Procs[CurProc].RetSymIdx` was still 17, but the `retArg` passed to
`EmitProcEpilog` was -1.

The actual clobber was the local `pi` in `ParseSubroutine`. That variable holds
the current procedure index and is later used by the parser epilogue:
`EmitProcEpilog(Procs[pi].RetSymIdx)`. The managed aggregate local zeroing path
for i386/aarch64 reused the same local for helper lookup:
`pi := FindProc('PXXMemZero')`. After that, `pi` named the helper procedure
(`PXXMemZero`, with `RetSymIdx = -1`) instead of `MakeR`, so the final epilogue
skipped the record-return aggregate copy and emitted only `leave; ret`.

Fix: `compiler/parser.inc` now uses a separate `helperPi` for the `PXXMemZero`
lookup/call, preserving the current-procedure `pi` until the final epilogue.

Landed:
- `1df5c76 fix(parser): preserve proc index during managed zeroing`
- `4e1ce6c chore(stable): pin default v14`

Test coverage restored:
- `test/test_const_record_temp_managed.pas` is back in the i386, aarch64, and
  arm32 cross suites.
- `test/test_managed_record_temp_init.pas` is back in the i386 and aarch64 cross
  suites; arm32 already covered it.

Validation passed:
- Direct i386/aarch64/arm32 repros now print the expected managed-field lengths
  and values.
- `make test`
- `make cross-bootstrap` (aarch64, arm32, i386 byte-identical)
- `make test-i386`
- `make test-aarch64`
- `make test-arm32`
- `make stabilize && make pin`

Stable default is now v14:
`28453d6ebd82757771d0fafc6c8fe165c674a3210807a3560908b6fef5d36a1f`.
