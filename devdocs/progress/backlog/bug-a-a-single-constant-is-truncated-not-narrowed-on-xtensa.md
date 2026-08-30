---
slug: bug-a-a-single-constant-is-truncated-not-narrowed-on-xtensa
title: "xtensa's IR_CONST_INT truncates a Single constant, the defect riscv32 was just fixed for"
track: A+S
prio: 25
type: bug
blocked-by: []
status: new
owner: ""
created: 2026-08-30
summary: "LATENT, and measured to be latent: ir_codegen_xtensa.inc's IR_CONST_INT has no tySingle arm, so a Single constant takes Low32 of its DOUBLE bit pattern -- the low mantissa half -- exactly as riscv32 did before frankC fixed it. Is64BitXtensa and Is64BitRISCV32 are character-identical, both excluding tySingle. It cannot fire today because NO float program compiles for xtensa at all: softfloat.pas needs calloc and the backend emits no dynamic segment. Filed rather than fixed because the fix is unverifiable while that holds."
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
