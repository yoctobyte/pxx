---
slug: bug-a-aarch64-passes-a-variadic-float-in-an-fp-register-so-glibc-reads-zero
title: "aarch64: a float in a VARIADIC argument tail is passed in an FP register, so a real C callee reads 0.00 — and every argument after it is wrong too"
track: A
prio: 55
type: bug
status: done
created: 2026-09-03
found-by: frankB
owner:
blocked-by: []
summary: "FIXED 2026-09-03, all three sites at once. `sprintf(buf, '[%.2f]', 3.5)` through a dynamic import of the target's own glibc printed `[0.00]` on aarch64 against `[3.50]` everywhere else, and with a following integer `'[%d %.2f %d]', 1, 3.5, 2` gave `[1 0.00 0]` -- THE ARGUMENT AFTER THE FLOAT LOST TOO, the signature of a slot-counting disagreement rather than a value bug. AAPCS64 puts a variadic floating-point argument in the FP bank on AArch64 Linux, which this ticket settled BY MEASUREMENT against glibc and not by reading the spec; pxx routed it through x0..x7 on both sides. INVISIBLE TO EVERY pxx-vs-pxx TEST because caller and callee were wrong in the same direction: the same program through crtl's own `sprintf` printed `[3.50]`, self-consistently, and every C variadic test in the suite was native-only where the defect does not exist. THE FIRST ATTEMPT FIXED THE CALLER ALONE, MEASURED GREEN AGAINST GLIBC, AND WAS REVERTED -- it inverted which side was broken (`printf(\"%.2f\", x)` through crtl went 3.00 -> 0.00) rather than reducing the number of broken sides. The landed fix is caller (one per-ARGUMENT class vector feeding the one ABIA64SlotWalk, replacing a variadic arm that used pxx's internal all-GP convention), callee (the variadic-save prologue stores d0..d7 at save-area offset 64, and the overflow anchor asks the placement walk instead of comparing a combined named count against 8) and va_arg/va_start (`__pxx_va_arg_a64_fp` for the FP region; `__pxx_va_start_impl` now takes BYTE offsets, because a seeder that converts slot counts can only know one target's layout). Both directions are wired and green at once: the aarch64 row of `test_pascal_varargs_external` (foreign callee, fpc oracle) and the new `test/cvararg_fp_bank_cross.c` on five targets (pxx callee, gcc oracle). Positive control run: disabling the callee's FP selection alone makes both fire on aarch64 and neither on native."
---

# The measurement

```pascal
program d1;
function sprintf(buf: Pointer; fmt: PChar): Integer; cdecl; varargs; external 'libc.so.6';
function puts(s: PChar): Integer; cdecl; external 'libc.so.6';
function fflush(f: Pointer): Integer; cdecl; external 'libc.so.6';
var b: array[0..127] of Char;
begin
  sprintf(@b[0], PChar('[%.2f]'), 3.5);        puts(@b[0]);
  sprintf(@b[0], PChar('[%d %.2f %d]'), 1, 3.5, 2); puts(@b[0]);
  fflush(nil);
end.
```

| build | row 1 | row 2 |
| --- | --- | --- |
| fpc 3.2.2 (x86-64) | `[3.50]` | `[1 3.50 2]` |
| pxx x86-64 | `[3.50]` | `[1 3.50 2]` |
| pxx arm32 | `[3.50]` | `[1 3.50 2]` |
| **pxx aarch64** | **`[0.00]`** | **`[1 0.00 0]`** |

`tools/run_target.sh aarch64` for the cross rows. **arm32 is the control that
matters**: same rig, same qemu, same real glibc, and it is correct — so this is
not the harness, the sysroot or the emulator, it is aarch64's variadic argument
placement.

**Row 2 is the sharper one.** The trailing `2` prints as `0`, so the callee and
the caller disagree about how many slots the float consumed, not merely about
where its bytes are. That is what AAPCS64 §6.4.2 describes: in a call to a
variadic function every argument in the variadic part is passed as if it were an
integer argument — general registers, then the stack — and the FP register bank
is not used at all. Passing the double in `v0` leaves the general slot the callee
reads untouched and shifts everything after it.

Not verified: which site does it. `ABIA64CdeclArgSlot` and the variadic arms in
`ir_codegen_aarch64.inc` (the ones testing `ProcVariadic`) are where to look, and
the fix has to know the FIXED parameter count to know where the variadic part
starts.

# Why no existing test could see it

**pxx's own `crtl` reads the argument back from the same wrong place.** The
equivalent C program compiled by pxx *without* `--system-libs=c`, so that
`sprintf` comes from `lib/crtl`, prints `[3.50]` on aarch64 — correct-looking,
and it proves nothing, because both halves were built by the same compiler out
of the same belief. That is precisely the self-consistency
`bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee`
exists to show is worthless for a calling convention, and here it is with a
worked example.

# THE ORACLE — and a correction to my own note of an hour ago

`bug-a-an-aggregate-argument-is-a-pointer-by-construction-on-aarch64` and
`bug-a-c-the-variadic-struct-abi-is-still-a-pointer-on-aarch64-arm32-and-riscv32`
both say their first deliverable is an oracle, and I added a note to both
(`2dd981a7b`) concluding that the missing piece is a LINKER. **That note is
correct about a static mixed link and it is incomplete as an answer to "is there
an oracle", which is the question those tickets actually ask.**

A mixed **link** is not required. A mixed **call** is, and it already works:

- **`~/.cache/pxx-cross/aarch64/lib/` and `.../arm32/lib/` hold a complete
  glibc** — `libc.so.6`, `libm.so.6`, `ld-linux-aarch64.so.1`, the nss modules —
  installed by `tools/install_qemu.sh`, and `run_target.sh` already points
  `QEMU_LD_PREFIX` at it.
- pxx can already emit a **dynamic import** for those targets
  (`external 'libc.so.6'`), and it resolves and runs.
- So a pxx-compiled caller and a **gcc-compiled glibc** exchange arguments
  across a real ABI boundary, with the observable being the callee's own
  formatted output. No cross gcc, no cross ld, no lld, nothing to install.

That is a genuine external reference for **any ABI question expressible as a
call into libc**: variadic tails (this ticket), by-value aggregates
(`struct`-taking libc entry points are thin on the ground, but `qsort`'s
comparator, `memcpy`'s sizes and the `printf` family cover argument placement,
promotion and slot counting), and float ABI. It does NOT cover a pxx-compiled
CALLEE receiving from a gcc-compiled caller — for that direction the linker
really is needed, and `qsort` with a pxx comparator is the exception that
reaches it through a function pointer.

**riscv32 and xtensa are not covered either way**: both refuse dynamic symbols
outright (`target riscv32: external (dynamic) symbols are not supported on this
target`), and there is no sysroot for them.

I am leaving the linker note where it is on both tickets and adding a pointer to
this section rather than rewriting it, because it is true about the thing it
describes; what was wrong was letting it stand as the answer to a question with a
cheaper answer.

# 2026-09-03, later — THE CALLER HALF, BUILT AND REVERTED, AND WHAT IT PROVED

Do not start this as a caller fix. I did, it works, and it is half a change.

## What I built and what it measured

`ABIA64CdeclArgSlot` derives each argument's class from
`Procs[procIdx].Params[pi]`, so it answers "not floating point" for every
argument past `ParamCount` — correct for a fixed signature and wrong for a
variadic tail, where there is no parameter and the class has to come from the
ARGUMENT's own type (`IntToTypeKind(IRTk[IRA[argNode]])`, the idiom arm32's
C-ABI arm already uses, and arm32 is the target that gets this right).

Collecting that class vector in the push loop and placing both the fixed prefix
and the tail from it made the oracle agree exactly:

| | before | with the caller half |
| --- | --- | --- |
| `sprintf(b,'[%.2f]',3.5)` via glibc, aarch64 | `[0.00]` | **`[3.50]`** |
| `'[%d %.2f %d]',1,3.5,2` via glibc, aarch64 | `[1 0.00 0]` | **`[1 3.50 2]`** |
| `test_pascal_varargs_external` on aarch64 | one row differs | **matches fpc** |

**So AAPCS64 §6.4.2 is settled by measurement and not by reading: a variadic
floating-point argument goes in the FP bank on AArch64 Linux.** glibc says so.

## Why it is reverted

`printf` in `lib/crtl` is a pxx-compiled VARIADIC CALLEE reached through the same
C-ABI call arm, and its aarch64 register-save prologue
(`cparser.inc`, `TARGET_AARCH64` arm of the variadic save) stores **x0..x7 only**,
with the comment *"aarch64 saves x0..x7 as one 8-byte GP area (the pxx value
model carries floats as GP bits)"*. That is a deliberate, self-consistent
internal choice: caller and callee both use the GP bank, so pxx-to-crtl works and
only a foreign callee sees the divergence.

Fix the caller alone and the pair inverts. Measured, with the caller half in:

```
printf("separate=%.2f\n", r);        ->  separate=0.00      (was 3.00)
printf("nested=%.2f\n", one(1.5));   ->  nested=0.00        (was 3.00)
```

That is not a regression to be worked around; it is the other half of the same
defect becoming visible. **A change that makes glibc right and crtl wrong is not
progress**, so it is out of the tree rather than parked in it.

## What the whole fix needs

1. **Caller** — the class vector above; ~20 lines in the C-ABI arm of
   `ir_codegen_aarch64.inc`, and it is written and measured, above.
2. **Callee** — the `TARGET_AARCH64` variadic-save prologue must also store
   `v0..v7` into an FP region of `__pxx_va_save`, and the overflow-area
   computation must count the two banks SEPARATELY (it currently uses
   `ProcNamedGP + ProcNamedFP > 8`, which is the all-GP model).
3. **`va_arg` lowering** — aarch64 must select the GP or FP area by the argument
   type the way the x86-64 arm does, seeding `gp_offset`/`fp_offset` for 8 GP
   and 8 FP slots rather than SysV's 6 and 8. The `__pxx_va_elem` block already
   has both offsets and `__pxx_va_arg_fp` already exists, so this is
   parameterisation and not new machinery.

All three land together or the tree is worse than it is now. Its verification is
cheap and complete: `test_pascal_varargs_external` on aarch64 (glibc as callee)
plus any crtl `printf("%f")` C program on aarch64 (pxx as callee) — the two
directions that must both be green at once.

## What IS landed from this attempt

`ABIA64SlotWalk` in `abi.inc`: the AAPCS64 placement walk split out to run over a
per-ARGUMENT class vector, with `ABIA64CdeclArgSlot` now building that vector
from the parameter list and calling it. Behaviour-identical — every aarch64 row
of `make test-core` is unchanged — and it is the mechanism step 1 needs, so the
next attempt starts from one walk with two sources rather than writing a second
walk. `PXXDBG=a.a64fp` prints the class each parameter gets, which is how I
established the classification was correct before looking at placement.

# 2026-09-03, later still — FIXED, ALL THREE SITES, BOTH DIRECTIONS GREEN AT ONCE

The three sites the previous section listed, in the order they appear in a call:

1. **Caller** (`ir_codegen_aarch64.inc`) — the variadic arm that called
   `EmitCallArgRegsA64` (pxx's INTERNAL all-GP convention) is **gone**, not
   fixed. Both the direct and the indirect C-ABI arms now build one per-ARGUMENT
   class vector and run one `ABIA64SlotWalk` over it: `A64CdeclArgIsFp` takes the
   class from the PARAMETER inside the declared list (so a by-ref float stays
   integer-class) and from the ARGUMENT's own type past it, which is exactly
   `Arm32CdeclArgKind`'s shape on the 32-bit target that already got this right.
   One placement path on this target instead of two rules that disagreed past
   `ParamCount`.
2. **Callee** (`cparser.inc`, the `TARGET_AARCH64` variadic-save prologue) — now
   stores `d0..d7` at save-area offsets 64..120 beside `x0..x7` at 0..56, and the
   overflow anchor asks `ABIA64NamedStackBytes` instead of comparing
   `ProcNamedGP + ProcNamedFP` against 8. A named parameter spills to the caller
   stack when its OWN bank fills; the combined count is the all-GP model and it
   put the anchor in the wrong place the moment a named float existed.
3. **`va_arg` / `va_start`** — `__pxx_va_arg_a64_fp` walks the FP region
   (8 slots of 8 at offset 64, so it ends at 128) and `__pxx_va_arg_cross` keeps
   the GP one. `__pxx_va_start_impl` now takes **byte offsets** rather than slot
   counts: the save-area layout is per-target and a seeder that converts counts
   can only know one target's, which is the mechanical reason aarch64 could not
   have an FP region before. x86-64's numbers are unchanged, just computed in
   the frontend.

`ABIA64VecStackBytes` is the vector-sourced twin of `ABIA64CdeclStackBytes` — a
variadic call cannot use the parameter-sourced one, because a float in the tail
displaces a GP slot and the stack block would be under-counted.

## The two directions, measured together

| | before | now |
| --- | --- | --- |
| `sprintf(b,'[%.2f]',3.5)` into glibc, aarch64 | `[0.00]` | `[3.50]` |
| `'[%d %.2f %d]',1,3.5,2` into glibc, aarch64 | `[1 0.00 0]` | `[1 3.50 2]` |
| 9 ints then a double, into glibc, aarch64 | — | `[1 2 3 4 5 6 7 8 9 2.25]` |
| 9 doubles (one past the FP bank), into glibc | — | `[1.00 ... 9.50]` |
| `test_pascal_varargs_external` on aarch64 | one row differs | matches fpc 3.2.2 |
| `cvararg_fp_bank_cross.c` through crtl, aarch64 | (not covered) | matches gcc |

Both are wired: the aarch64 row of `test_pascal_varargs_external` (foreign
callee) and the new `test/cvararg_fp_bank_cross.c` on native/aarch64/arm32/
i386/riscv32 (pxx callee). **Neither alone can tell a correct convention from
two sides wrong in the same direction**, which is the entire history of this
ticket — every C variadic test in the suite was native-only, and on x86-64 the
defect does not exist.

## The positive control, run

Disabling ONE line of the fix — the callee's FP-bank selection in `va_arg`,
leaving the caller half in, which is precisely the half-change that was reverted
on the first attempt — and rebuilding:

```
c1/native   PASS  (control does not fire here)
c2/native   PASS
c1/aarch64  FAIL   separate=3.00 -> 0.00 ; mix d=2.25 -> 0.00, b=9 -> 0
c2/aarch64  FAIL   scaled=6.00 -> 2.00 ; inter 1:1.50 -> 1:0.00 ; many=55.00 -> 0.00
```

So the new guard fires on the target it is about and stays silent on the one it
is not, and it fires on the specific wrong state that looked green before. The
compiler was restored and rebuilt to the same binary sha (`a85892f216a9`) before
anything was committed.

## One thing found and deliberately not fixed

The hidden-destination block on this same arm saves `x0..x7` across the
destination evaluation and not `v0..v7`, and its own comment says the arguments
are in both. Wider now than it was, still not reachable by any program:
`bug-a-aarch64-an-aggregate-result-s-destination-is-evaluated-with-the-fp-argument-bank-unsaved`,
filed with the shape that would reach it and an explicit "do not land it without
a program that fails first".

## Log
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 1c2219596.
