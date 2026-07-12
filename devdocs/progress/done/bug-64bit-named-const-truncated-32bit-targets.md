---
prio: 80  # silent wrong VALUES on every 32-bit target, incl. ESP32 (riscv32/xtensa)
---

# 64-bit named constants are truncated to 32 bits on the 32-bit targets

- **Type:** bug (constant lowering) — **Track A**
- **Status:** done
- **Opened:** 2026-07-12, hit by Track B: `lib/rtl/p256field.pas` computed
  garbage on i386/arm32/riscv32 while being bit-exact on x86-64/aarch64.

## Symptom

A named constant declared with a 64-bit value comes out **truncated to its low
32 bits and sign-extended** on i386, arm32 and riscv32. Correct on x86-64 and
aarch64.

```pascal
program u68;
const
  K0 = UInt64($FFFFFFFFFFFFFFFF);
  K1 = UInt64($00000000FFFFFFFF);
  K3 = UInt64($FFFFFFFF00000001);
  RR3 = UInt64($00000004FFFFFFFD);
var a: UInt64;
begin
  a := K0; WriteLn(a);   { want 18446744073709551615  -> got 18446744073709551615  (right by luck: -1) }
  a := K1; WriteLn(a);   { want 4294967295            -> got 18446744073709551615 }
  a := K3; WriteLn(a);   { want 18446744069414584321  -> got 1 }
  a := RR3; WriteLn(a);  { want 21474836477           -> got 18446744073709551613 }
end.
```

`K0` is right only by accident (all-ones truncates to -1 and sign-extends back
to all-ones), which is exactly the kind of coincidence that hides this.

## What is NOT affected

- **Direct literals**: `a := UInt64($FFFFFFFF00000001)` is correct on i386.
- **Typed-const arrays**: `const K: array[..] of UInt64 = ($428a2f98..., ...)`
  is correct — which is why `lib/rtl/sha512.pas` (80 64-bit round constants) is
  fine and no shipping library is currently broken.

So it is specifically the scalar `const NAME = <64-bit value>` declaration path.
The value survives `ConstEval` (an Int64); it appears to be the constant's
inferred TYPE that collapses to a 32-bit ordinal, so the 32-bit backends
materialize only the low word and sign-extend it. On the 64-bit targets every
register is 64 bits wide, so the truncation is invisible — which is why this has
sat undetected.

## Why it matters

Silent wrong VALUES, no error, no crash — the worst failure mode, and it lands
squarely on the code most likely to use big hex constants: crypto, hashing, bit
masks, magic numbers.

It is not a 32-bit-is-irrelevant-for-perf case either: **ESP32 is riscv32 /
xtensa**. Pastella's realm crypto (the killer-app demo: the same gossip protocol
on a $3 chip and a laptop) would silently compute garbage on device while
passing every test on the dev box.

## Fix

Give a named constant whose value does not fit in 32 bits (or which is written
through a `UInt64` / `QWord` / `Int64` cast) a 64-bit type, so the 32-bit
backends materialize the full value.

## Acceptance

- The program above prints the four wanted values on i386, arm32 and riscv32.
- `lib/rtl/p256field.pas` (`test/lib_p256field.pas`) is bit-exact on every
  target — same output as x86-64.
- Regression test in `test/`, run cross.
- self-host byte-identical; `make test` green.

## Log
- 2026-07-12 — resolved, commit b1ff20f3.
