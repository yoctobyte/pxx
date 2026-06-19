# const record param with a managed (dynarray) field crashes by-ref on i386 + aarch64

- **Type:** bug (compiler / codegen, cross-target)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (found while adding cross tests for
  bug-const-byref-record-param-temp)

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

Blocks managed-record value APIs (bignum `TBigInt`, JSON nodes, etc.) from being
exercised through `const` params on the 32-bit/aarch64 cross targets. The
x86-64 path (the self-host gate) is unaffected, so it does not block bootstrap —
but the cross suites can only cover the *unmanaged* const-record-temp case until
this is fixed. Once fixed, fold the managed-record variant
(`test/test_const_record_temp_managed.pas`) into the i386/aarch64/arm32 cross
suites.

## Log
- 2026-06-19 — opened by track A. Found via the const-record-temp cross tests;
  isolated to the managed-field-by-ref read (named var crashes too, not just
  temporaries). i386 + aarch64 affected; arm32 + x86-64 fine.

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
