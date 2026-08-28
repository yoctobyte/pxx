---
slug: bug-a-set-membership-truncates-the-test-value-on-32-bit-backends
title: "`in` truncates a 64-bit test value to 32 bits on i386 and arm32"
track: A
type: bug
prio: 25
status: backlog
found: 2026-08-28
found-by: frankwasm (measured on five targets while implementing the wasm32 `in` arm)
---

## The fact

```pascal
var q: Int64;
q := 4294967297;            { 2^32 + 1 }
WriteLn(q in [1,2,3]);
```

| target | answer | |
| --- | --- | --- |
| x86-64 | FALSE | correct |
| aarch64 | FALSE | correct |
| wasm32 | FALSE | correct |
| **i386** | **TRUE** | wrong |
| **arm32** | **TRUE** | wrong |

The items here are 1, 2 and 3 — small. It is the **test value** that is
truncated, which makes this a different defect from
`bug-p-set-membership-item-constant-truncated-to-32-bits` (the item constants,
all targets, parser-level). The two are independent and either can be fixed
without the other.

## Root cause

`compiler/ir_codegen386.inc:3078`:

```pascal
IREmitNode386(IRA[argNode]);   { eax = test value }
EmitB($89); EmitB($C1);        { mov ecx, eax }
```

A 64-bit value arrives in `edx:eax`; only `eax` is moved to `ecx`, and every
subsequent `cmp ecx, imm32` sees the low half. The high half is dropped with
nothing testing it.

`compiler/ir_codegen_arm32.inc:2520` is the same shape — `mov r1, r0` where a
64-bit value occupies r0/r1 under AAPCS.

The 64-bit backends are correct by construction: x86-64 uses `mov rcx, rax`,
aarch64 `mov x1, x0` with `cmp x1, x2`. `riscv32` and `xtensa` have no
`SPECIAL_IN` arm and refuse `in` outright — a refusal, not a wrong answer, so
they are not affected.

## Fix

Compare both halves on the 32-bit backends. The cheapest correct shape is to
test the high half against the item's sign-extension and fold that into the
existing accumulator (`edx` on i386, `r4` on arm32) — the accumulator is already
there and already has the right lifetime, so no new register pressure.

The alternative — refuse a 64-bit test value on 32-bit targets, as riscv32 and
xtensa already effectively do — is worse than it sounds: it would turn working
i386 code into a compile error for the sake of a case that is almost never
reached. Prefer the fix.

## The two defects can cancel, which is worth knowing when testing

On arm32, `4294967296 in [4294967296..4294967300]` answers **TRUE** — the right
answer, reached wrongly. The test value truncates to 0 and the parser truncates
the bounds to 0..4, so `0 in [0..4]` is TRUE. x86-64 and aarch64, which have only
the parser defect, answer FALSE.

**So a test that only checks arm32 against a correct expectation on that input
would pass.** Fixing either defect alone will make that case go red on arm32,
and that red will be progress, not a regression.

## Repro

```
printf 'program t;\nvar q: Int64;\nbegin q := 4294967297; WriteLn(q in [1,2,3]); end.\n' > /tmp/t.pas
./compiler/pascal26 --target=i386 /tmp/t.pas /tmp/t386 && /tmp/t386   # TRUE; should be FALSE
./compiler/pascal26              /tmp/t.pas /tmp/t64  && /tmp/t64     # FALSE — the control
```

Measured at branch `wasm` sha 954b56b53, compiler 2e68d018ccac; x86-64 and i386
run natively, arm32/aarch64 under `qemu-arm`/`qemu-aarch64`, wasm32 under node.
Every cell in the table above was run; none is by inspection.

## Reachability — read this before ranking it up

Same caveat as the sibling ticket: a set item list is normally 0..255 and a
64-bit test value against one is rare. prio 25 reflects reach, not severity —
it is a silent wrong answer, which is why it is filed at all.
