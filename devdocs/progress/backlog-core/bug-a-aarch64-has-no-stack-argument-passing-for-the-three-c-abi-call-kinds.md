---
slug: bug-a-aarch64-has-no-stack-argument-passing-for-the-three-c-abi-call-kinds
track: A
prio: 30
type: bug
status: new
found: 2026-08-31
found-by: frankA
owner: ""
blocked-by: []
summary: "TWO OF THE THREE KINDS LANDED 2026-08-31; the CDECL INDIRECT call is what is left. The external-direct call and the variadic external call now place arguments past the banks in an AAPCS64 stack area, and so does the callee (EmitParamSpillsForTarget's ProcCdecl arm, which had the same refusal). All of them ask ONE oracle -- ABIA64CdeclArgSlot in abi.inc -- instead of each counting its own lo/hi, which is what let the register half be right and the stack half be absent three times over. Measured against gcc on a 12-argument mixed int/double signature and a 10-double one, both banks overflowing: pxx now matches gcc exactly on x86-64, aarch64, arm32, i386 and riscv32. STILL OPEN: ir_codegen_aarch64.inc:3574 refuses a cdecl INDIRECT call past 8 arguments -- a different restructure, because that block has an injected Self and the callee address pushed below arg0. The old summary said \'nothing reaches it today\'; that was false and is corrected in the body -- a nine-int C function reaches it, lua/src/lcode.c has one, and it broke lua and sqlite on aarch64 the moment a C function always used the C ABI."
---

# aarch64: no stack-argument passing for the three C-ABI call kinds

- **Filed:** 2026-08-31 by frankA, on fixing the internal four. Original finding
  frankS's.
- **~~Nothing reaches this today.~~ CORRECTED 2026-08-31 by frankC — ordinary C
  source reaches it.** The original claim was about the EXTERNALS pxx declares,
  and it is true of those; it is not true of the population that actually
  matters, which is C code pxx COMPILES. Measured on `116ceec70b8e`, one file,
  five targets:

  ```
  static int nine(int a,...,int i) { return a*1 + b*2 + ... + i*9; }
  aarch64  COMPILE ERROR: a cdecl routine with more than 8 integer or 8
           floating-point parameters is not supported yet
  arm32    285      i386  285      riscv32  285      x86-64  285
  ```

  A nine-parameter C function is not exotic. The refusal was invisible because
  the C-ABI gate used to exclude C programs, so a C program's own functions took
  the positional path, which has no such limit; with
  bug-c-a-c-function-s-calling-convention-depends-on-the-target ruled option A a
  C function always uses the C ABI, and the population is now every C program.
  *(That last sentence is read from the gate, not separately measured; the five
  rows above are measured.)*

  **This is what kept the shape out of the test suite too.** `cabi_bridge.c`,
  `cabi_intra.c` and `c_abi_pure_c_control.c` gained `mix4` and an EIGHT-int
  shape on 2026-08-31 — eight and not nine precisely because nine makes every
  other shape in those files unreachable on aarch64. So the one target with no
  stack-argument implementation is also the one holding the test down to eight.

## The three sites, `compiler/ir_codegen_aarch64.inc`

| kind | guard |
| --- | --- |
| external call | `Procs[procIdx].ParamCount > 8` |
| variadic external call | `nArgs > 8` |
| cdecl indirect call | `nArgs > 8` |

There is a fourth, adjacent guard — `(lo > 8) or (hi > 8)`, "exceeds 8 int or 8
fp argument registers" — which is about one BANK overflowing and is the same
defect seen from the other side.

## Why the internal helper does not answer it

`EmitCallArgRegsA64` assigns register `i` to argument `i`. AAPCS64 for C does
not: it classifies each parameter and draws from two independent banks, so
argument 3 can be `d0` and argument 4 `x3`. A by-REF float counts as a POINTER
and belongs in the integer bank — the x86-64 twin of that line once put
`var d: Double` in an SSE register while the callee read a pointer from a GPR,
which is `bug-a-a-by-ref-float-param-through-a-cdecl-fnptr-is-classified-sse`
and was a segfault rather than a wrong number.

## What it owes before anyone starts

AAPCS64's stack rule is not "the ninth argument onward": it is NSAA, and once an
argument is placed on the stack the banks are considered exhausted for the rest
of the call, with per-type alignment of each stack slot. Getting that wrong is a
crash at a library boundary, which is why this is parked rather than
approximated.

Verify against the gcc oracle (`tools/gcc_diff_probe.sh --target=aarch64`), not
against our own second implementation.


---

# TWO OF THREE LANDED 2026-08-31 — frankC, in the C-ABI stack-argument group

Taken because it turned out to be a hard blocker on
[[bug-c-a-c-function-s-calling-convention-depends-on-the-target]], which I had
said it was not. That was wrong and the correction is worth more than the fix:
**this ticket's own summary said "nothing reaches it today"**, which was true of
the externals pxx DECLARES and false of the C code pxx COMPILES. Under option A
every C function uses the C ABI, so the population became every C program, and
the corpus found it immediately:

| subject | before the flip | with the flip, before this fix |
| --- | --- | --- |
| c-testsuite aarch64 | 219 pass | **217 pass, 2 fail** (00170, 00204) |
| lua cross aarch64 | six scripts pass | **build error in `lua/src/lcode.c`** |
| sqlite threads aarch64 | pass | **build error in `sqlite3.c`** |

Baseline measured, not assumed: stashed the group, rebuilt clean origin/master
(`3d5308a75742`), and a nine-int C function prints 285 on aarch64.

## What landed

**One oracle, `ABIA64CdeclArgSlot` in `abi.inc`**, answering "register or stack,
which bank, which index, what offset" for one argument. The caller and the
callee each used to count their own `lo`/`hi`, get the register half right, and
refuse the stack half separately — which is this ticket's own diagnosis of the
parent bug ("a missing mechanism wearing four names") arriving a second time.
AAPCS64 stage C for scalars: independent NGRN/NSRN, a full bank sends its
argument to NSAA and sets **that** bank to 8 while the other keeps allocating,
and every scalar slot is 8 bytes — which is AAPCS64's own rounding for a type of
8 bytes or less, so the area needs no per-argument alignment.

- **External / bodied-cdecl direct call** — both refusals gone (`ParamCount > 8`
  and `(lo > 8) or (hi > 8)`). Temps are read by OFFSET rather than popped,
  because the outgoing block must be built while they are all still live; the
  stack half runs first so it cannot disturb an argument register the register
  half has already loaded; one `add sp` after the call drops everything.
- **Variadic external call** — deleted rather than rewritten. It is the FIFTH
  spelling of a mechanism `EmitCallArgRegsA64` already implements, and that
  helper's own comment names the other four. It now just calls it.
- **Callee, `EmitParamSpillsForTarget`'s ProcCdecl arm** — reads a stack argument
  from `[x29 + 16 + off]`, the same anchor the positional arm next door uses,
  with the offset from the shared oracle.

## Gate

Against **gcc**, which is the right instrument here and was available: a
12-argument `(int,double)*6` signature and a 10-double one, both banks
overflowing to the stack. pxx matches gcc exactly on x86-64, aarch64, arm32,
i386 and riscv32 — five targets, one expected string, no pxx-side authority
anywhere in it.

## STILL OPEN: the cdecl indirect call

`ir_codegen_aarch64.inc:3574` still refuses past 8 arguments. Deliberately left,
and the ticket stays open for it:

- Nothing in the corpus reaches it — a function POINTER with more than eight
  arguments, where the direct case is `printf` and `lcode.c`.
- Its block is not the same shape: the callee address is pushed BELOW arg0 and
  an injected `Self` shifts the argument indices, so the offset arithmetic is a
  different restructure rather than the same one a third time.

Closing this ticket on two kinds out of three would be the false-green this
repo keeps naming. The remaining kind is one refusal, at one line, with the
oracle it needs already written.
