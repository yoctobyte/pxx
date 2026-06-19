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
