# 64-bit gaps in pinned v9: `xor` operator, large shifts, 64-bit hex literals

- **Type:** bug (compiler)
- **Status:** backlog
- **Owner:** — (track A)
- **Opened:** 2026-06-19 (track B, building the RNG library)
- **Relation:** blocks the full feature-random-library (xoshiro256** /
  splitmix64 need all three), feature-hashing-library (SHA/CRC need `xor` +
  64-bit rotates), and 64-bit-limb approaches in feature-bignum-library. Track B
  shipped an interim 32-bit LCG (`lib/rtl/random.pas`) to route around them.

## Symptoms (all against `stable_linux_amd64/default/v9`)

1. **`xor` operator unrecognized.** `and` / `or` / `shl` / `shr` work; `xor`
   does not:
   ```
   c := a xor b;   -> pascal26: error: undefined variable (xor)
   ```
   Fails for Integer, Int64 and UInt64 operands alike.

2. **`shl` / `shr` by >= ~31 yield 0**, even on 64-bit operands:
   ```
   u := 1; u := u shl 40;   -> u = 0     (expected 2^40)
   s shr 32 / s shr 33      -> 0
   ```
   Small shifts (e.g. `shr 16`) are fine.

3. **64-bit hex literals truncate to 32 bits.**
   ```
   s := $853C49E6748FEA9B;  -> only the low 32 bits ($748FEA9B) survive
   ```
   By contrast, **Int64 decimal literals + 64-bit add/compare/store work**
   (`a := 10000000000; a > 4000000000` -> true), so this is specific to the
   hex-literal path and to the shift/xor operators, not 64-bit storage in
   general.

## Repro

```pascal
program t; var a,b,c: Integer;
begin a:=12; b:=10; c := a xor b; writeln(c); end.   { error: undefined variable (xor) }
```
```pascal
program t; var u: UInt64;
begin u:=1; u:=u shl 40; writeln(u); end.             { prints 0 }
```

## Direction

- Add `xor` to the operator keyword/precedence handling (lexer + expr parser),
  for Integer / Int64 / UInt64.
- Fix `shl`/`shr` to use a 64-bit shift on 64-bit operands (the count masking /
  the 32-bit shift instruction selection looks wrong above ~31).
- Parse 64-bit hex literals to full width (no truncation to 32 bits).

Each is independently testable; a combined test (build a known 64-bit constant
via hex, shift it, xor it, compare to the decimal form) would cover all three.

## Log
- 2026-06-19 — opened by track B while writing the RNG library. Shipped a 32-bit
  LCG interim so the RNG/dice work could proceed; the modern 64-bit generator,
  hashing, and 64-bit bignum limbs wait on these fixes.
