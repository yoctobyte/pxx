---
slug: bug-a-set-membership-32-bit-backends-truncate-the-set-constant
title: "i386/arm32/riscv32 truncate the set CONSTANT in `x in [consts]` (the test-value half is already fixed)"
summary: "The 32-bit backends compare the low word plus a fits-in-int32 flag, so a set element above 2^31 truncates: `1 in [4294967297]` is TRUE and `4294967297 in [4294967297]` is FALSE. x86-64 and aarch64 were fixed in 831919a7d; these three were measured failing the same three rows and are the residual."
track: A
type: bug
prio: 20
status: backlog
found: 2026-09-05
found-by: frankO (measured on all five runnable targets while fixing the 64-bit half)
---

## The fact, measured on every runnable target

`test/test_set_in_64bit_const.pas`, run cross at `831919a7d`:

```
x86_64   A FALSE B TRUE  C TRUE  D FALSE E TRUE F TRUE G TRUE   <- correct
aarch64  A FALSE B TRUE  C TRUE  D FALSE E TRUE F TRUE G TRUE   <- correct
i386     A TRUE  B FALSE C FALSE D FALSE E TRUE F TRUE G TRUE
arm32    A TRUE  B FALSE C FALSE D FALSE E TRUE F TRUE G TRUE
riscv32  A TRUE  B FALSE C FALSE D FALSE E TRUE F TRUE G TRUE
```

A is `q=1; q in [4294967297]` (must be FALSE), B is the same set with
`q=4294967297` (must be TRUE), C is `4294967296 in [4294967296..4294967300]`.

## Why this is NOT the ticket that was just closed

`831919a7d` widened two narrowings on the shared path — `loVal, hiVal` in
`ParseSetMembershipAST` and the `Integer(IRIVal[...])` casts — and added
`CmpRcxImm` so x86-64 could encode an immediate it physically could not hold.
That is enough for the two 64-bit targets. **It cannot be enough here**, and
the mechanism is a different one:

`done/bug-a-set-membership-truncates-the-test-value-on-32-bit-backends`
installed the current 32-bit shape, which compares only the LOW word of the
test value and then ANDs in a "the test value fits in a signed int32" flag
(i386: `sar eax,31; cmp eax,edx; sete al`, arm32: the `mov r2, r0, asr #31`
block). That is correct **while every constant fits in int32**, which was true
when it was written. With a constant above 2^31 it fails both ways:

- row A: the constant truncates to 1, the small test value matches it, and the
  fits-flag is 1 — so a non-member reads as a member;
- row B: the genuine member matches on the low word, but the fits-flag is 0
  because the test value does not fit in int32 — so a real member is zeroed.

## What a fix has to do

Compare **both words per item**, rather than one word plus a whole-expression
flag: an item `K` matches iff `low32(q) = low32(K)` and `high32(q) = high32(K)`.
Ranges are worse — a signed 64-bit `<`/`>` on a 32-bit target is a two-word
compare with a borrow — and the item loop's jump patch sites are hand-emitted
per backend, which is why this is sized work and not a cast deletion.

The machinery already exists: `done/bug-64bit-named-const-truncated-32bit-targets`
made 64-bit *named constants* materialise correctly on these three targets
(`EmitLoadConst64RISCV32`, `Is64Bit386`, `Is64BitArm32`), so the constant can
be got into registers at full width. What is missing is the compare.

wasm32 is already correct by construction — `WasmEmitSetIn` has a `wide` flag
and `PushOrd(x: Int64)` — and is not affected. xtensa cannot be run on this
host and was not measured; its SPECIAL_IN walk declares `itemNode, hi: Integer`
like riscv32's, so it is a candidate rather than a finding.

## Reachability — read before ranking

Same argument as the parent: real Pascal sets are 0..255 and a set item at or
above 2^31 is close to nonexistent. Prio 20 because it is a silent wrong answer
on three cross targets, not because anything is blocked on it. **Do not rank it
down on "x86-64 is fine"** — that is the native-only blind spot CLAUDE.md names,
and here the two 64-bit targets are green precisely because they are 64-bit.

## Repro

```
make compiler/pascal26
for t in i386 arm32 riscv32; do
  ./compiler/pascal26 --target=$t test/test_set_in_64bit_const.pas /tmp/s_$t
done
qemu-i386 /tmp/s_i386
qemu-arm /tmp/s_arm32
qemu-riscv32 /tmp/s_riscv32
```

All three print **`SETIN64 FAILED 5`**, identical row for row, measured at
`831919a7d`:

```
FAIL A_LOW_MATCH: got TRUE want FALSE
FAIL B_EXACT: got FALSE want TRUE
FAIL C_RANGE: got FALSE want TRUE
FAIL H_INT32_MAX_PLUS1: got FALSE want TRUE
FAIL I_MIXED_WIDTH_SET: got FALSE want TRUE
```

aarch64 prints `SETIN64 OK`. That the three 32-bit targets fail the SAME five
rows identically is the evidence they share one mechanism rather than three.

**MEASURED UNDER AN EMULATOR, NOT ON HARDWARE, and the distinction is not
pedantry here** — a cross red seen under qemu and one seen on a real chip are
different claims, and only the first is available on this box. All four runners
are `qemu 10.2.1 (Debian 1:10.2.1+ds-1ubuntu3.2)`, host kernel `7.0.0-30`.
The failure is a wrong constant in emitted code rather than anything the
emulator interprets differently, so emulation is very unlikely to be the
cause — but nobody has run it on hardware and this ticket does not claim
otherwise. (`regression-test-core-c-crtl-wait` is the standing example on this
repo of a cross red that WAS the emulator: seven's qemu 8.2.2 against plexus's
10.2.1, same compiler bytes, opposite answers.)

## Blast radius is bounded to SPECIAL_IN — checked, not assumed

The obvious worry, raised by frankZ: `cmp rcx, imm32` sign-extending is a fact
about x86-64 comparisons in general, not about sets, so if the general
comparison lowering shared the defect this ticket would be much larger than
its title. It does not. Measured at `831919a7d` **and** against the pre-fix
pin, both `CMPWIDE OK`:

```pascal
q := 4294967297;
if q =  4294967297 ... if q <> 4294967296 ... if q > 4294967296
if q >= 4294967297 ... if q <  4294967300 ... if q <= 4294967297
case q of 4294967297: ...        { also correct }
```

All ten rows right on both compilers, so the general path already materialises
a wide immediate properly and only the hand-emitted SPECIAL_IN walk bypassed
it. The same probe is worth re-running on the 32-bit targets before writing
their fix: if plain `if q = 4294967297` is already correct there, whatever it
uses is the machinery the item loop should be reusing rather than a new
two-word compare written from scratch.
