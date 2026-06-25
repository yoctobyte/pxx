# bug: `not` on an Int64 yields a boolean, not the bitwise complement

- **Type:** bug (codegen / typing — `not` operator on 64-bit integers)
- **Status:** backlog
- **Track:** A
- **Opened:** 2026-06-25
- **Found-by:** Track B, porting X25519 (`lib/rtl/x25519.pas`) — TweetNaCl's
  `~x` / arithmetic-shift idioms broke until every bitwise `not` on an `Int64` was
  rewritten as `-x - 1`.

## Symptom

`not` on a plain `Int64` **variable** is correct, but `not` applied to an `Int64`
**expression** (an arithmetic/shift subexpression, or a cast like `Int64(5)`)
miscompiles — the result is wrong (the bitwise complement isn't produced; the
operator appears to be typed as boolean for the 64-bit expression):

```pascal
var x, r: Int64;
begin
  x := 5;
  r := not x;          writeln(r);   { -6  OK   }
  r := not (x);        writeln(r);   { -6  OK   }
  r := not (x - 1);    writeln(r);   { 5   WRONG (want -5) }
  r := not (x shr 1);  writeln(r);   { 3   WRONG (want -3) }
  r := not Int64(5);   writeln(r);   { 4   WRONG (want -6) }
end.
```

`writeln(not Int64(0))` even prints `TRUE`. So the trigger is **`not <Int64
expression>`**, not the variable case. `and` / `or` / `xor` / `shl` / `shr` on
`Int64` are all correct (verified — SHA-256 and ChaCha20-Poly1305 over `Int64`
pass their RFC vectors); only `not` of a 64-bit non-trivial operand is wrong.

## Workaround in use

Bitwise complement written with the two's-complement identity `~x = -x - 1`:

```pascal
{ ~x }            -x - 1
{ ~(b-1) = -b }   -b
{ arithmetic >>n of a negative x, using logical shr: }
  -(((-x - 1) shr n)) - 1
```

`lib/rtl/x25519.pas` (`Asr64`, `Sel25519`) uses these — see
[[track-b-workarounds]]. Revert to plain `not` once fixed.

## Likely cause

The `not` operator's result type / opcode selection picks the boolean path for a
64-bit integer operand (32-bit `not` may be fine — worth checking `LongWord`).
Should emit a 64-bit bitwise NOT.

## Acceptance

- `not x` for `x: Int64` returns the bitwise complement (`not Int64(0) = -1`) on
  all targets; check `LongWord`/`Integer`/`Int64` and signed/unsigned.
- Regression test.
