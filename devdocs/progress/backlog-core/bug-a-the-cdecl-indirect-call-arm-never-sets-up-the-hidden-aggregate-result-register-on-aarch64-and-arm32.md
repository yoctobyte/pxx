---
slug: bug-a-the-cdecl-indirect-call-arm-never-sets-up-the-hidden-aggregate-result-register-on-aarch64-and-arm32
track: A
prio: 60
type: bug
blocked-by: []
status: backlog
found: 2026-09-05
found-by: frankC
owner: frankC
summary: "aarch64 and arm32: an indirect call through a CDECL function-pointer whose result is an aggregate SEGFAULTS. IR_CALL_IND's cdecl arm in ir_codegen_aarch64.inc (~3877) and ir_codegen_arm32.inc (~3415) never reads IRCallDest, so the hidden aggregate-result register (x8 / r0) holds whatever was there and the callee writes through it. riscv32 and x86-64 are correct. The discriminator is the CONVENTION, not the language: a pure-PASCAL reproducer segfaults the moment its fn-pointer type is marked `cdecl`. Every C function pointer takes this arm, because CParseFnSigGroup sets ProcCdecl unconditionally, so ALL C code returning a struct through a callback is dead on both targets."
---

# The cdecl indirect-call arm never sets up the hidden aggregate-result register on aarch64 and arm32

## Reproducer — C, and the same thing in Pascal

```c
int printf(const char *, ...);
struct P3 { int x, y, z; };
static struct P3 mk3(int s){ struct P3 p; p.x=7; p.y=11; p.z=13; return p; }
int main(void){
  struct P3 (*fp)(int) = mk3;
  struct P3 a = mk3(0);  printf("direct %d %d %d\n", a.x, a.y, a.z);
  struct P3 b = fp(0);   printf("indirect %d %d %d\n", b.x, b.y, b.z);
  return 0; }
```

Measured at `e36f2f04c` + the offset-zero fix, binary `4c547865c4b7`:

```
x86_64   rc=0    direct 7 11 13 | indirect 7 11 13
i386     rc=0    direct 7 11 13 | indirect 7 11 13
riscv32  rc=0    direct 7 11 13 | indirect 7 11 13
aarch64  rc=139  direct 7 11 13 | SIGSEGV
arm32    rc=139  direct 7 11 13 | SIGSEGV
```

`direct` is correct everywhere; only the indirect call dies. **Size is not the
variable** — 1 int, 2 ints, 3 ints, a bare `char`, and an 8-int array all
segfault identically on both targets, and all five are correct on riscv32.

## It is NOT a C-frontend defect, and the control that says so

The obvious control — the same program in Pascal — is **correct** on aarch64 and
arm32, which reads as "the backend can do this, so the C frontend is what is
broken". That reading is wrong, and it is wrong because the control was drawn
from the wrong population: an ordinary Pascal `function(s: Integer): TP3`
fn-pointer is not `cdecl`. Add the keyword and nothing else:

```pascal
type TMk = function(s: Integer): TP3; cdecl;
```

```
PASCAL cdecl aarch64  SIGSEGV
PASCAL cdecl arm32    SIGSEGV
PASCAL cdecl riscv32  indirect 7 11 13
PASCAL cdecl x86_64   indirect 7 11 13
```

Identical to the C matrix, four targets out of four. **The convention selects
the broken arm; the language only decides how often you land on it.**

## Cause

`IR_CALL_IND` branches on `CProcUsesCAbi(procIdx)`, which is exactly
`ProcCdecl[procIdx]`. The IR is the same shape in both languages —
`call_ind` / `lea <temp>` / `copy_rec`, verified identical node-for-node
between the C and Pascal dumps — and the `lea` of the unnamed temp is the
hidden destination, reached through `IRCallDest[node]`, not through IRA/IRB.

- `ir_codegen_riscv32.inc:3973` handles `IRCallDest` **at the top of
  `IR_CALL_IND`, above the cdecl branch**. Green.
- `ir_codegen_aarch64.inc`: the cdecl arm (~3877-3990) pushes callee and args,
  walks `ABIA64VecWalkN`, `ldr x16` / `blr x16`, drops the block, and handles
  only a float or narrow-int return. It never mentions `IRCallDest`. The
  *internal* arm below it (~3997) does, popping the destination into **x8**,
  and `IR_VIRTUAL_CALL` (~4034) does too.
- `ir_codegen_arm32.inc`: same shape, same omission; its internal arm loads the
  destination into r0.

So the callee's `EmitAggregateDestStash` prologue reads an uninitialised x8/r0
and stores through it.

## Fix

Mirror the internal arm inside the cdecl arm on both backends: push
`IRCallDest[node]` deepest (below the callee word), load it into x8 / r0
immediately before the `blr`/`blx`, and add one more 16-byte (aarch64) /
4-byte (arm32) slot to both the reach check and the post-call `add sp`.
`EmitCallArgRegsA64`'s `xtra2` parameter already expresses exactly this for the
internal arm; the cdecl arm hand-rolls its block and needs the slot added by
hand.

## The register choice is the part to get right, and riscv32 is the precedent

Do not read "add `IRCallDest`" as mechanical. The cdecl arm's own comment says
it is for *a dlsym'd C function*, and for a genuinely external AAPCS callee the
hidden aggregate pointer is **x8** on aarch64 but **r0** on arm32, with every
declared argument shifted by one. That is NOT what the callee here wants: the
callee reached through a C function pointer is pxx-compiled, and its prologue
(`EmitAggregateDestStash`) reads pxx's INTERNAL destination register.

The two green targets both resolve it the same way, and they resolve it in
favour of the internal convention:

- **riscv32** handles `IRCallDest` at the top of `IR_CALL_IND`, *above* the
  cdecl branch, and its own comment is explicit that the register is the same
  one the direct path uses "deliberately, because the callee prologue has no
  idea how it was reached, so an indirect call that used a different register
  would be a second convention for one thing."
- **x86-64** is green through the identical `ProcCdecl` branch.

So the fix mirrors the INTERNAL arm inside the cdecl arm (x8 on aarch64, r12 on
arm32 — arm32's internal arm uses r12, not r0), rather than implementing the
external AAPCS sret shape. Anything else grows a second convention for one
thing, which is the shape
`devdocs/dev/normalise-dont-special-case.md` warns about.

The alternative fix — restore the guard the arm's comment says it already has,
so C-mode indirect calls take the internal path at all — is worth pricing
first: `CProcUsesCAbi` is exactly `ProcCdecl[procIdx]` with no language test,
so the comment describes an intent the code does not implement. If that guard is
the real missing piece, it fixes both backends in one place. **Measure which
before editing either.**

## Blast radius

Larger than the tickets it was found under. Every C function pointer gets
`ProcCdecl := True` from `CParseFnSigGroup`, so **any** C callback returning a
struct by value is dead on aarch64 and arm32 — a callback shape busybox, lua and
sqlite all use. It is invisible to the dev loop because that runs on x86-64,
where the same arm is correct.

## Found by

Adding cross-target coverage for
[[bug-c-a-field-past-the-first-eight-bytes-of-an-indirect-call-s-struct-result-reads-back-as-offset-zero]].
`test/c_fnptr_struct_result_fields.c` is wired on x86-64, i386 and riscv32 with
aarch64 and arm32 named as deliberately absent, citing this ticket; add them to
that Makefile row when this closes.
