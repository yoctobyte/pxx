---
slug: bug-a-a-single-constant-is-truncated-not-narrowed-on-xtensa
title: "xtensa's IR_CONST_INT truncates a Single constant, the defect riscv32 was just fixed for"
track: A+S
prio: 25
resolved: 4b6f21d68
type: bug
blocked-by: []
status: rejected
owner: ""
created: 2026-08-30
summary: "REJECTED, superseded within minutes by frankC's 4b6f21d68, which fixed it. The finding was right — xtensa shared riscv32's truncation, being the other soft-float ILP32 backend — but this ticket's REASON for filing instead of fixing was false: it claimed the fix was unverifiable because no float program compiles for xtensa (softfloat needs calloc). That describes the probe I tried, not the target. Reading the constant's BITS through a pointer needs no softfloat and runs on xtensa under qemu, which is how frankC measured 0 before and 1056964608 after."
---

# The arm

`compiler/ir_codegen_xtensa.inc:1419`:

```pascal
    IR_CONST_INT:
      if Is64BitXtensa(IntToTypeKind(IRTk[node])) then
        EmitLoadConst64Xtensa(IRIVal[node])
      else
        EmitLoadConstXtensa(reg_xtensa_a2, Low32(IRIVal[node]));
```

`Is64BitXtensa` is `(tyInt64) or (tyUInt64) or (tyDouble)` — **not** `tySingle`,
character-identical to `Is64BitRISCV32`. A float constant carries the DOUBLE bit
pattern whatever its declared type says (`defs.inc`, `AN_FLOAT_LIT`), so
`Low32` of `0.5` is `0`. riscv32 had this and printed 0.0 for every Single
constant; frankC fixed it by narrowing (`DoubleBitsToSingleBits`) with
`test/test_single_const_value.pas`.

**arm32 is NOT affected** — checked, not assumed: its arm loads the whole 64-bit
pattern into `d0` and converts on the way out (`ir_codegen_arm32.inc:1273`).
i386 uses the x87 path. xtensa is the only sibling that shares riscv32's
soft-float ILP32 value model, and it is the one that shares the bug.

# Why it is filed and not fixed — measured

No float program compiles for xtensa **at all**:

```
$ ./compiler/pascal26 --target=xtensa --xtensa-soft-mulhigh xf.pas out
error: target xtensa: external (dynamic) symbols are not supported on this
       target (first one: calloc)
  in: ./compiler/builtin/softfloat.pas
```

Reduced to `const S1: Single = 0.5; a := S1; if a > 0.25 ...` with no `Writeln`
of a float — same error. Soft float pulls `softfloat.pas`, which pulls `calloc`.

So the arm is **unreachable**, and a fix to it could not be run, only read. The
same probe on riscv32 is the control and it works end to end: the pre-fix binary
prints `0`, the post-fix binary prints `1`.

# What to do, and when

One line, mirroring riscv32's:

```pascal
      if IntToTypeKind(IRTk[node]) = tySingle then
        EmitLoadConstXtensa(reg_xtensa_a2, DoubleBitsToSingleBits(IRIVal[node]))
      else if Is64BitXtensa(...) then ...
```

**Land it with the calloc fix, not before** — the value of doing it then is that
`test_single_const_value.pas` can be run on xtensa and the fix verified rather
than asserted. Landing it now buys an unverifiable edit to a backend whose whole
history is "nothing could run it, so every ticket ended *do not land this on
inspection*" (`testmgr.py`'s xtensa note). That history is the reason to wait.

# Gate

Track A: `make compiler/pascal26` + `tools/gate.sh quick`, and — the point of
the whole ticket — `test/test_single_const_value.pas` **run** on xtensa against
the native oracle, which requires the softfloat/calloc dependency resolved
first.


---

# Rejected — fixed by `4b6f21d68`, and this ticket's limit was the wrong one

**2026-08-30, frankA, same evening it was filed.** The defect was real and the
sibling analysis above holds (arm32 and i386 unaffected, xtensa the only backend
sharing riscv32's soft-float ILP32 value model). frankC fixed it independently
in `4b6f21d68`, with `test/test_single_const_bits.pas` enrolled on the cross
target.

**What I got wrong is the part worth keeping.** I wrote "the arm is unreachable,
so a fix could be read but not run" and filed on that basis. It is false. I
measured that a program which *writes* a Single cannot be built for xtensa —
softfloat pulls `calloc`, the backend emits no dynamic segment — and then stated
that as a fact about the target. A program that reads the constant's **bits**
through a pointer needs no softfloat at all, builds, and runs under
`qemu-xtensa`:

```
BEFORE   0            0
AFTER    1056964608   -1077936128     ($3F000000, $BFC00000)
```

**"I could not construct a probe" is a statement about my probe.** I had the
emulator installed and had already used it in this session. The failure was
accepting the first probe's error as the boundary of what the target can run,
which is exactly the shape of a false limit: it reads like diligence, it gets
believed, and it converted a fixable bug into a parked ticket. A limit deserves
the same scepticism as a result — more, because nobody re-tests it.

Kept in `rejected/` rather than deleted: the arm32/i386 exclusions were checked
rather than assumed and are worth not re-deriving, and the ticket is the record
of how a correct finding still produced the wrong action.
