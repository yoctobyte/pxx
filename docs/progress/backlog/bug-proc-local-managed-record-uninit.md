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
