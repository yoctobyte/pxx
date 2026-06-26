# Proc-local managed record not zero-initialised on entry → first-call miscompute

- **Type:** bug (compiler / codegen)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, bignum factorial demo, on pinned v10)
- **Severity:** high — affects every record-with-a-managed-field local in a
  procedure (bignum, collections, JSON nodes, any dynarray/string-bearing record).

## Symptom

A procedure with a local record that contains a dynamic array (or other managed
field) miscomputes on its **first** call; later calls are correct. The local is
not zero-initialised on entry, so the first `:=` into it (a managed assignment
that releases the "old" value) operates on stack garbage and corrupts the result.

```
5! = 240    { first call  — WRONG (should be 120; note 240 = 2*120) }
5! = 120    { second call — correct }
10! = 3628800  { correct }
```

## Minimal repro (pinned v10)

```pascal
program t; uses bignum, strutils;
procedure Fact(n: Integer);
var acc: TBigInt; i: Integer;          { TBigInt = record neg: Boolean; limbs: array of Int64; end }
begin
  acc := BigFromInt(1);
  for i := 2 to n do acc := BigMulSmall(acc, i);
  writeln(n, '! = ', BigToStr(acc));
end;
begin
  Fact(5);   { prints 240 — WRONG }
  Fact(5);   { prints 120 — correct }
  Fact(10);  { correct }
end.
```

The same computation in the **main program body** (not a procedure) is always
correct. Only the proc-local managed record is affected, and only on first entry.

## Direction

Zero-initialise managed-typed locals (records containing dynarray/AnsiString/
interface fields, and bare managed locals) at procedure entry before any managed
assignment runs — so the first `:=` doesn't DecRef/free stack garbage. (This is
the local-init analogue of the ESP managed-local nil-init fix in the project
history.)

## Impact / interim

bignum's factorial demo is written entirely in the **main body** to dodge this
(`examples/bignum/factorial.pas`). Real client code can't always do that, so this
should be fixed before record-valued APIs (bignum/collections/JSON) are
ergonomic in procedures.

## Log
- 2026-06-19 — found on pinned v10 while writing the bignum factorial demo.
  Clean repro above; first-call-only, managed-record-local specific.

## Resolution (2026-06-19) — FIXED (x86-64 + arm32)

Root cause was NOT the proc's declared managed-record local (those are zero-inited
by the parser's prologue pass, parser.inc ~8772) — it was the **hidden
aggregate-result temp**. `IRAppendCall` allocates a scratch local to receive a
record-returning call's result; it is created during IR lowering, AFTER that
prologue zero-init pass. When such a call sits on an untaken branch (the minimal
trigger: a `Result := F(0); Exit` early-exit that the inputs never reach), the
temp is never filled, yet the proc's scope-exit cleanup releases its managed
fields and frees stack garbage — corrupting the FIRST call only (bignum's
`5! = 240`). The `SymIsHiddenArgTemp` nil-init mechanism existed but (a) the temp
wasn't marked, and (b) the per-target nil-init only zeroed one pointer-sized slot,
missing a managed field past offset 0 in a multi-field record.

Fix:
- `IRAppendCall` (ir.inc) marks the aggregate-result scratch `SymIsHiddenArgTemp`
  when the return record has managed fields.
- The `SymIsHiddenArgTemp` prologue nil-init in all four backends now zeroes the
  FULL record extent (`RecSize`, via `PXXMemZero` on the cross targets / `rep
  stosb` on x86-64) when the temp is a managed record larger than a pointer,
  instead of a single slot.

Validated x86-64 + arm32: `test/test_managed_record_temp_init.pas` (the
factorial-shape repro) in test-core + the arm32 cross suite; bignum factorial in
a procedure now gives `5! = 120` on the first call. Self-host + cross-bootstrap
byte-identical; all 3 cross suites output-identical. On i386 + aarch64 the same
program is still blocked by the SEPARATE managed-record function-return bug
(`bug-const-managed-record-param-byref-crash`), so the test is x86-64 + arm32
only there.
