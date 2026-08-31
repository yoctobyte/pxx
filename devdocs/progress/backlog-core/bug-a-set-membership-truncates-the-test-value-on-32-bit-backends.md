---
slug: bug-a-set-membership-truncates-the-test-value-on-32-bit-backends
title: "`in` with a 64-bit element is wrong on ALL FOUR 32-bit backends, in two different ways"
track: A
type: bug
prio: 25
status: backlog
found: 2026-08-28
found-by: frankwasm (measured on five targets while implementing the wasm32 `in` arm)
owner: frankA
summary: "FIXED on all four 32-bit backends 2026-08-31. Wider than filed: riscv32 and xtensa have the same defect (they gained their `in` arms after this was written), and there are TWO shapes, not one. A constant set literal is SPECIAL_IN, compared inline -- that shape silently answered TRUE for 2^32+1. A set VARIABLE is IR_BINOP tkIn -- that shape did not compile at all, because a 64-bit LEFT operand routed `in` into the 64-bit ARITHMETIC emitter, which has no tkIn arm. One root cause: `in` was being treated as 64-bit arithmetic when it is a membership test with a Boolean result. Test test_set_in_64bit_element.pas, 21 rows, six targets. NOTE: FPC 3.2.2 truncates and so disagrees on 7 rows -- deliberate, see decide-does-in-truncate-an-out-of-range-element-or-answer-false."
---

> **DANGLING SHAS BY DESIGN.** The commit shas in this ticket live on branch
> **`wasm`**, not on `origin/master` — it was filed from the wasm lane's
> standalone checkout, which pushes to its own branch. `progress.sh check`
> flags them `SIDE-BRANCH-SHA` and that is correct rather than a defect: the
> measurement was taken where the work is. **Branch permission is not merge
> permission** — nothing on `origin/wasm` is pre-approved for master.
> Twelve-hex values like `2e68d018ccac` are **binary sha256** prefixes of
> `compiler/pascal26`, not commits at all, and will not resolve as objects.
> — frankwasm, 2026-08-30

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

---

## WARNING for whoever fixes this: on arm32 two defects CANCEL on the range shape

Added 2026-08-28 by the coordinator, from frankwasm's re-measurement **under qemu** (its
earlier cross-target claim was made "by inspection"; `qemu-arm` and `qemu-aarch64` were on
`PATH` the whole time, and inspection would have been half wrong).

The table above is the **scalar** shape — `q in [1,2,3]` with a large `q` — and it is correct:
arm32 answers TRUE and TRUE is wrong.

On the **range** shape it is the other way round. `2^32 in [2^32..2^32+4]` answers **TRUE on
arm32, which is the correct answer** — reached because the truncation of the test value and
the truncation on the bound side cancel.

**So a correct partial fix makes a currently-passing case start failing.** Repair the test
value alone and the range shape breaks; repair the bound alone and it breaks the other way.
Whoever takes this must:

1. pin **both** shapes — scalar and range — before touching anything;
2. expect the range row to go red mid-fix, and **not read that as a regression introduced by
   the fix**; it is a compensating error becoming visible;
3. only judge the work by both rows green together.

> **A PASSING RESULT PRODUCED BY TWO ERRORS THAT CANCEL IS INDISTINGUISHABLE FROM A PASSING
> RESULT PRODUCED BY CORRECTNESS** — and it converts the first honest half-fix into what looks
> like a regression.

Related: `feature-a-a-refusal-is-a-claim-with-a-date-on-it` — same signature as the rest of that
family, a state carrying no information because two conditions read identically.


---

## Fixed 2026-08-31 — and it was wider than filed, in both directions

### Two more backends

The ticket names i386 and arm32. **riscv32 and xtensa have it too** — they were
not exempt, they simply had no `in` arm when frankwasm measured; both gained one
later the same week. Measured before touching anything, at binary `73396b86f09a`:

```
q := 4294967297;  WriteLn(q in [1,2,3]);     { oracle: FALSE }
  i386 TRUE   arm32 TRUE   riscv32 TRUE   xtensa TRUE
  x86-64 FALSE   aarch64 FALSE
```

### Two shapes, and only one of them is the reported symptom

`in` reaches codegen by two different routes, which is the trap
`normalise-dont-special-case.md` names:

| source shape | lowering | symptom before the fix |
| --- | --- | --- |
| `q in [1,2,3]` (all-constant) | `SPECIAL_IN`, compared inline | silently **TRUE** |
| `q in s` (a set variable) | `IR_BINOP` `tkIn` | **failed to compile** |

The second shape is not in the ticket and is the louder bug:

```
$ pascal26 --target=i386 setv.pas /tmp/x
error: target i386: 64-bit binop operator not yet supported
```

...on all four backends, identically. Anyone reproducing only the filed repro
would have fixed `SPECIAL_IN`, closed the ticket, and left `q in s` uncompilable.

### One root cause under both

**`in` was being dispatched as 64-bit ARITHMETIC because its element is
64-bit.** Each backend routes a binop to its dedicated 64-bit emitter on
`Is64Bit(tk) or Is64Bit(lhsTk) or Is64Bit(rhsTk)` — but `in` has a **Boolean**
result and its right operand is a **set address**, so the only thing that
matched was the element, and the 64-bit emitter has no `tkIn` arm.

The same mismatch explains the quiet half: every compare in `SPECIAL_IN` is
32 bits wide, so the high dword was never read. x86-64 is correct for free —
its `cmp rcx, imm32` is REX.W and the immediate is sign-extended to 64 bits.

### The fix, one idea at four sites

1. **Exclude `tkIn` from the 64-bit dispatch.** It removes only cases that
   previously raised an error, so it cannot change a program that worked.
2. **`IR_BINOP tkIn`:** if the element is 64-bit, saturate it to 256 when the
   high word is nonzero, then let each backend's **existing** unsigned
   `0..255` range check decide. Deliberately reusing that check instead of
   adding a second one that could disagree with it. Must happen before the
   left operand is spilled — the high word lives in the register the right
   operand is about to overwrite.
3. **`SPECIAL_IN`:** compute "does this value fit in a signed 32-bit int" once
   (`hi = lo asr 31`) and AND it into the result. Branch-free on i386/arm32/
   riscv32 so it needs no patch site and cannot desynchronise the item loop's
   own jumps; xtensa uses branches because it has no immediate ASR emitter here.

### Verified

`test/test_set_in_64bit_element.pas` — 21 rows, wired for native + aarch64 +
riscv32 + arm32 + i386 + xtensa. **All six targets match**, including the
Char/Integer/in-range control rows that a fix could have broken while making the
2^32+1 rows go FALSE.

**Regression, object-level:** compiling all 140 Pascal sources with the pre-fix
binary `73396b86f09a` and the post-fix `338a7cbd49c5` gives **byte-identical
objects** — i386 137/137, and the other three below. That is expected by
construction: every arm added is guarded by "the element is 64-bit AND the op is
`tkIn`", and that combination previously either errored or was already wrong.

### FPC disagrees, and we are diverging on purpose

FPC 3.2.2 **truncates** and answers TRUE; 7 of the 21 rows differ. That is now a
recorded decision rather than an accident:
[[decide-does-in-truncate-an-out-of-range-element-or-answer-false]]. This fix
did not choose a semantics — it moved four backends onto the answer x86-64 and
aarch64 already gave. What no ruling changes is that all six must answer alike.
