---
slug: bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386
title: "The C frontend advertises __GNUC__ and __i386__, then refuses the inline asm that pair invites"
track: C
prio: 55
type: bug
status: open
created: 2026-09-04
found-by: frankD
summary: "`cparser.inc:7876` refuses any non-empty inline-asm template unless `TargetArch = TARGET_X86_64`. Five busybox TUs hit it on i386 and none on x86-64: procps/powertop.c, networking/tls_sp_c32.c, tls_pstm_mul_comba.c, tls_pstm_sqr_comba.c (all `non-empty template ... not i386`) and tls_pstm_montgomery_reduce.c (`earlyclobber constraint \"=&d\" is not supported`, cparser.inc:7491). NOT a mis-gating problem that dropping a predefine would fix: pxx answers `__GNUC__=2` AND `__i386__` on i386, and the sources ask for exactly that pair -- `#if ALLOW_ASM && defined(__GNUC__) && defined(__i386__)` (tls_sp_c32.c:216) -- while powertop.c:500 is a bare `#ifdef __i386__` with no __GNUC__ gate at all. The source is selecting the arm we told it to select. The fix is to encode the template on i386, not to withdraw a claim. **SCOPED 2026-09-04 (frankC) AND IT IS FOUR JOBS, NOT TWO — the ENCODER IS NOT ONE OF THEM:** `AsmDispatch` already has `mul`/`adc`/`sbb`/`cpuid`, and all thirteen instruction forms these arms use assemble BYTE-IDENTICALLY in 32- and 64-bit mode (gas, diff clean), because 32-bit operand size is the default in both and no REX is reachable. What the refusal actually stands in front of is that **`AN_ASM`'s span means AsmBytes on x86-64 and an InlineAsmLine index on i386** (`AsmParseBody` routes 5 of 6 targets to a text capture), so job 1 is a sink decision — recommend giving the AT&T reader a TEXT renderer over giving i386 a second AN_ASM form. **Job 1 alone is NOT sufficient for three of the four files that report it:** the i386 caller-saved pool is 5 registers (`ebx` is callee-saved), and a `\"m\"` operand costs a register here because it is pinned to its ADDRESS, so mul_comba wants 5 with 3 free and sqr_comba 4 with 3. Rendering `\"m\"` as a frame slot — which gcc does, which the encoder already supports via AOP_MEM, and which helps x86-64 too — makes both fit exactly, so it is the FIRST job. **Job 2 as written unblocks NOTHING:** behind montgomery_reduce's earlyclobber sit an unsupported `\"g\"` class (5 uses) and a subscript output `_c[LO]` that the plain-lvalue rule refuses in both its macros, so removing the `&` refusal moves the message and compiles no file. `powertop.c` is a fourth job on its own — `cpuid` writes `\"=b\"`, and `ebx` needs a save/restore pair no other TU here wants."
---

# What the refusal is

Measured 2026-09-04 at the 394-applet scope (`tools/busybox-applets-394.txt`),
binary sha256 `1968c7a7da57`, commit `5f598d4a7`.

```
FAIL i386 procps/powertop.c                    @520  non-empty template ... not i386
FAIL i386 networking/tls_sp_c32.c              @257  non-empty template ... not i386
FAIL i386 networking/tls_pstm_mul_comba.c      @280  non-empty template ... not i386
FAIL i386 networking/tls_pstm_sqr_comba.c      @514  non-empty template ... not i386
FAIL i386 networking/tls_pstm_montgomery_reduce.c @410 earlyclobber constraint "=&d"
```

`cparser.inc:7865-7877` runs its refusals **most specific first**, deliberately,
so the message names the missing thing rather than the outermost fact about it.
That design is why this ticket can be written at all — four of the five say
"not i386" and one says "earlyclobber", which are two different jobs.

## Why "just stop defining __GNUC__" is the wrong repair

Measured, not assumed:

```
$ pascal26            gnuc.c && ./a.out   ->  __GNUC__=2
$ pascal26 --target=i386 gnuc.c && run    ->  __GNUC__=2
```

and the sources gate on the pair we advertise:

```c
tls_sp_c32.c:216   #if ALLOW_ASM && defined(__GNUC__) && defined(__i386__)
tls_sp_c32.c:258   #elif ALLOW_ASM && defined(__GNUC__) && defined(__x86_64__)
powertop.c:500     #ifdef __i386__          /* no __GNUC__ gate at all */
```

So on i386 the source correctly selects an **i386** asm arm because we told it
we are GNU on i386. Withdrawing `__GNUC__` would push `tls_sp_c32.c` onto its
portable `#else` and look like a fix, and would do nothing for `powertop.c`,
which asks only about the architecture. It would also be a lie in the other
direction: we DO encode asm, just not here.

Note the inverse hazard this creates for anyone verifying under an older pin:
before `__GNUC__` was defined, these files took their portable arms and
compiled, so a green on a pin that predates it is correct about a different
compiler. See CLAUDE.md's `--pinned` note, which uses `tls_sp_c32.c` as its
example.

## Two jobs, not one

1. **Encode a non-empty template on i386.** The x86-64 path is
   `AttResetBindings` + `AttEncodeTemplate`, and with operands
   `CAsmBuildBlock` pins each to a register. i386 is the same instruction
   family with a narrower register file; whether `AsmDispatch` already
   encodes what these five need is the first thing to measure, not to argue.
2. **`=&d` earlyclobber** (`cparser.inc:7491`) is target-independent and is a
   separate, smaller job. Do not let it ride on job 1.

## Scope

x86-64 does not see any of this — all five compile there. It is one more member
of the class where the native target is the one with the blind spot; see
`feature-c-corpus-busybox-i386-the-second-architecture` for the other, larger
member (the host-header fallback).

# 2026-09-04, frankC — the five TUs are FOUR jobs, not two, and the encoder is not one of them

Scoping pass, read-only, at HEAD `162a22dd3`. Nothing below is a plan; each row
is a constraint census of the arm the i386 preprocessor actually selects, taken
from `library_candidates/busybox-frankC`.

## The instruction encoder already does all of it, and the bytes are the SAME

The ticket's job 1 says *"whether `AsmDispatch` already encodes what these five
need is the first thing to measure, not to argue."* Measured, two ways.

**It has the mnemonics.** `mul` (`asmenc.inc:1147`), `adc`/`sbb` (`1047`,
`1048` — added as "the two missing rows of this table"), `cpuid` (`846`),
`mov`/`add` from the base ALU set. Nothing the five arms name is absent.

**And every byte it would emit is mode-independent.** The thirteen instruction
forms those arms use, assembled by gas for both modes — 32-bit operands, base
registers below 8, `[ebp+disp]` frame slots — are **byte-identical**:

```
 8b 08     mov (%eax),%ecx        |  8b 08     mov (%rax),%ecx
 03 0a     add (%edx),%ecx        |  03 0a     add (%rdx),%ecx
 8b 48 04  mov 0x4(%eax),%ecx     |  8b 48 04  mov 0x4(%rax),%ecx
 13 4a 04  adc 0x4(%edx),%ecx     |  13 4a 04  adc 0x4(%rdx),%ecx
 19 c9     sbb %ecx,%ecx          |  19 c9     sbb %ecx,%ecx
 f7 27     mull (%edi)            |  f7 27     mull (%rdi)
 83 d7 00  adc $0x0,%edi          |  83 d7 00  adc $0x0,%edi
 0f a2     cpuid                  |  0f a2     cpuid
 8b 45 f8  mov -0x8(%ebp),%eax    |  8b 45 f8  mov -0x8(%rbp),%eax
 89 45 f4  mov %eax,-0xc(%ebp)    |  89 45 f4  mov %eax,-0xc(%rbp)
```

(all 13 rows compared, `diff` clean). That is not a coincidence: 32-bit operand
size is the default in both modes, and a REX prefix appears only for a 64-bit
operand or a register `>= 8`, neither of which these arms use. **So the refusal
at `cparser.inc:7959` is not standing in front of missing encoding work.**

## What it IS standing in front of: AN_ASM means two different things

`AsmParseBody` (`asmenc.inc:1944-1975`) routes **five of six targets** to a
`AsmParseBodyText*` capture, and only x86-64 to the byte encoder. So an
`AN_ASM` node's `Left`/`Right` are an **AsmBytes span on x86-64 and an
`InlineAsmLine` span on i386** — `ir_codegen386.inc:1634` replays lines through
`Asm386ProcessInlineLine`, which would read a byte offset as a line index.

The convention is per-TARGET and globally consistent today. Job 1 has to pick
one of two, and the choice is the actual design decision in this ticket:

- **give i386's `IR_ASM` a second, byte-span form** — much less code, and it
  puts two mechanisms behind one concept on one target, which is the smell
  `root-cause-over-microfix.md` names;
- **give the AT&T reader a TEXT sink** — one parser, two renderers, each target
  keeping exactly one convention. `asmatt.inc` parses into the `AsmOp*` globals
  and then calls `AsmDispatch`; a renderer that formats those same globals as
  the Intel lines `AsmParseBodyText386` produces swaps only the last step.

Recommending the second, and not landing either here: it is a change to a file
Track A owns and it wants its own commit.

## The pool is 5 on i386, not 9 — and that alone refuses two of the five

`CAsmPool` (`cparser.inc:7898`) is nine caller-saved x86-64 registers. On i386
the caller-saved set is `eax ecx edx esi edi` — **five** — because `ebx` is
callee-saved and pxx's prologue does not save it. Counting each arm against
that, with clobbers taken out first exactly as `CAsmBuildBlock` does:

| TU | operands wanting a register | free after clobbers | verdict |
| --- | --- | --- | --- |
| `tls_sp_c32.c` `sp_256_add_8` | 4 (`"=r"`×4, 3 tied) | 5 (`"memory"` only) | **fits** |
| `tls_pstm_mul_comba.c` `MULADD` | 5 (`"=rm"`×3 + `"m"`×2) | 3 (`%eax`,`%edx` clobbered) | **refuses** |
| `tls_pstm_sqr_comba.c` `SQRADD` | 4 (`"=rm"`×3 + `"m"`) | 3 (same clobbers) | **refuses** |

So "encode a non-empty template on i386" is **not sufficient for three of the
four** files that report it. The two comba files run out of registers, and the
reason is a design choice that costs nothing on x86-64 and everything here:

**a `"m"` operand is pinned to a register holding its ADDRESS.** gcc spills the
value to the frame and writes the operand as `-8(%ebp)`, using no register at
all. `CAsmBuildBlock` already allocates a temp local per operand and the
encoder already has the `[rbp+disp32]` form — the `AOP_MEM` operand the whole
pinning design is built on. Making `ATTBIND_MEM` render a frame slot instead of
`[reg]` takes both comba files from *one short* to *exactly fitting*, and it is
a **normalisation that helps x86-64 too** (every `"m"` there currently burns a
pool entry it does not need). Do this BEFORE the pool, not after: sizing a pool
against a cost that should not exist is how the wrong number gets defended.

## `"=b"` is a fourth job, and it is the only one that touches the prologue

`procps/powertop.c:500` is `cpuid`, and its four outputs are `"=a" "=b" "=c"
"=d"` — the register set the instruction writes, so **`ebx` is not negotiable
by us**. The pool note says callee-saved registers are absent "on purpose —
clobbering a callee-saved register here would break our caller". Supporting
this TU means a save/restore pair around the block for any fixed-register
constraint naming a callee-saved register. Small, self-contained, and nothing
else in the five needs it.

## And job 2 as written unblocks NOTHING — measured, and it changes the ranking

`tls_pstm_montgomery_reduce.c` is the one TU whose message is the earlyclobber,
and the ticket says *"a separate, smaller job. Do not let it ride on job 1."*
Both halves are true and the conclusion a reader draws from them is not: the
refusals run most-specific-first, so `&` is simply **the first of three** things
that file needs. Its i386 arm, in full:

```c
#define INNERMUL                                    /* line 86 */ \
asm("mull %4\n\t" "addl %3,%%eax\n\t" "adcl $0,%%edx\n\t"
    "addl %%eax,%0\n\t" "adcl $0,%%edx\n\t"
   :"=g"(_c[LO]), "=&d"(cy)
   :"0"(_c[LO]), "g"(cy), "g"(mu), "a"(*tmpm++) :"cc")

#define PROPCARRY                                   /* line 102 */ \
asm(... :"=g"(_c[LO]), "=r"(cy) :"0"(_c[LO]), "1"(cy) :"cc")
```

Behind the `&`, in the order `CAsmRefuseUnsupported` and `CAsmBuildBlock` would
reach them:

1. **`"g"` is not a supported class.** `CAsmClassSupported` reads `r`, `rm`,
   `mr`, `m` and the fixed-register letters; `g` (register / memory /
   immediate) is in neither list, and it appears **three times** as an input
   plus twice as the `"=g"` output.
2. **`_c[LO]` is not a plain variable.** Outputs are restricted to `AN_IDENT`
   so a subscript is not evaluated twice — a deliberate correctness rule, and
   this output is a subscript in both macros.

Removing the earlyclobber refusal therefore moves the message and compiles
nothing. **Rank it as what it is: a cleanup with no TU attached**, not the
smaller half of a two-TU ticket. (Earlyclobber itself is very likely a no-op
for us — every untied operand already gets its own pinned register, so `&`'s
guarantee holds by construction — but "the refusal is unnecessary" and "the
file compiles" are different claims and only the first is established here.)

## Summary of the decomposition

| job | unblocks | touches |
| --- | --- | --- |
| `"m"` → frame slot instead of a pinned register | 0 alone, prerequisite for 2 | `cparser.inc`, `asmatt.inc` |
| AT&T text sink + i386 pool | `tls_sp_c32`, and with the row above both combas | `asmatt.inc`, `cparser.inc` |
| callee-saved save/restore for a fixed-register constraint | `powertop.c` | `cparser.inc` |
| `"g"` class + non-plain-lvalue outputs + earlyclobber | `tls_pstm_montgomery_reduce.c` | `cparser.inc` |

Nothing above changes `ir_codegen386.inc`'s replay contract except job 2's
first bullet, which is exactly why the sink choice is the decision to make
first.
