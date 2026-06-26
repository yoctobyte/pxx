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

## Resolution (2026-06-25) — host targets

Two defects, both fixed:

1. **Typing (root cause).** The parser only trusted `not <operand>` as bitwise
   for an int LITERAL or IDENTIFIER; every other integer operand fell to the
   boolean path (`xor rax,1`), so `not Int64(0)` printed TRUE, `not (x-1)` etc
   were wrong. Extended the trust (`parser.inc`, `tkNot`) to three more
   authoritative-integer operand shapes: built-in ordinal value-casts
   `Int64(e)`/`Cardinal(e)` (AN_PTR_CAST, ASTIVal=-1) and the `Integer(e)`/
   `LongWord(e)` token-casts (AN_CALL, negative op id); and **pure
   arithmetic/shift** AN_BINOP (`+ - * div mod shl shr`; `shr` is lexed as an
   identifier so its op id is `Ord(tkIdent)`). `and`/`or`/`xor` and comparisons
   stay logical (a comparison binop is sometimes mistagged integer), so the
   compiler's own `not (a or b)` / `not (r and v)` keep self-host byte-identical.

2. **arm32 codegen (found while verifying).** arm32 `IR_NOT` did `mvn r0,r0` only
   — the high word `r1` was left intact, so even the already-bitwise `not x` for
   an `Int64` read as a 32-bit complement (`-6` → `4294967290`). Added the
   64-bit pair branch (`mvn r0,r0; mvn r1,r1`), mirroring i386's `eax:edx`.

Verified `not` over Int64 cast/arith/shift on **x86-64, i386, aarch64, arm32**
(LongWord complement checked by value). Gate: `make test` (self-host
byte-identical — neither change touches compiler self-build paths) +
`test-i386/aarch64/arm32` + `cross-bootstrap` all green. New regression
`test/test_not_int64_expr.pas` wired into the x86-64 base test and all three
cross sections.

**ESP not covered here** — riscv32 `IR_NOT` is unconditionally `xori a0,1`
(boolean, ignores type) and xtensa's non-64 path is `xor a2,1` (boolean for
32-bit ordinals too). That is a distinct pre-existing defect needing the
bare-metal qemu-system harness to verify; filed as
`bug-esp-not-always-boolean`. x25519 (the finder) runs on host, so the host fix
unblocks it.

Committed in 1abf43f.
