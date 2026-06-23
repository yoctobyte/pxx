# bug: cardinal/longword binary-op promotes to uint64 (FPC: int64)

- **Type:** bug (Track A — type promotion) — FPC-parity, wrong value on underflow
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC
- **Closed:** 2026-06-23
- **Severity:** low-medium (diverges only when the result underflows / exceeds int32)

## Resolution (2026-06-23)

`TypeArithmeticResult` (symtab.inc) returned `tyUInt64` whenever
`TypeCompareUnsigned(lhs,rhs)` was true — including two 32-bit unsigned operands
(Cardinal/LongWord/Word/Byte), so `cardinal(3) - cardinal(5)` evaluated as
2^64-2. Changed to return `tyUInt64` only when an operand is itself a 64-bit
unsigned type (`tyUInt64`/`tyNativeUInt`); otherwise `tyInt64`. Two
32-bit-or-narrower unsigned operands fit in Int64, so the result is signed —
matching FPC. `TypeCompareUnsigned` (relational comparison signedness) is
untouched.

Verified vs FPC `{$mode objfpc}`: `a-b` = -2, store-back wrap unchanged
(4294967295 / 0), `a+b` = 8, `uint64 - n` stays unsigned. Gate: `make test`
(self-host byte-identical) + FPC oracle. Closes bug-cardinal-expr-promotion.

## Symptom

A `cardinal - cardinal` expression used directly (not stored back into a 32-bit
variable) is computed as unsigned 64-bit in pxx, but FPC promotes the pair to a
signed `int64`:

```pascal
var a, b: cardinal;
begin a := 3; b := 5; writeln(a - b); end.
{ fpc: -2    pxx: 18446744073709551614  (2^64 - 2) }
```

## What is correct (controls)

`cardinal` is 32-bit in both (`sizeof = 4`), and wrap is correct when the result
is stored back into a 32-bit type:

```pascal
var c: cardinal; begin c := 0; c := c - 1; writeln(c); end.   { both: 4294967295 }
var c: cardinal; begin c := 4294967295; c := c + 1; writeln(c); end.  { both: 0 }
```

So only the **result type of the binary operation** differs: pxx widens
`cardinal op cardinal` to `uint64`, FPC to `int64`. Positive in-range results
agree; underflow / >int32 values diverge.

## Expected

Match FPC integer promotion: `cardinal`/`longword` operands whose result fits in
`int64` yield a signed `int64` expression (so `3 - 5` → `-2`), not `uint64`.

## Repro

`tools/fpc_diff_probe.sh` (`cardinal-sub`).
