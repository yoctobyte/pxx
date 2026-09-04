---
slug: bug-c-inline-asm-is-x86-64-only-so-five-busybox-tus-refuse-on-i386
title: "The C frontend advertises __GNUC__ and __i386__, then refuses the inline asm that pair invites"
track: C
prio: 55
type: bug
status: open
created: 2026-09-04
found-by: frankD
summary: "`cparser.inc:7876` refuses any non-empty inline-asm template unless `TargetArch = TARGET_X86_64`. Five busybox TUs hit it on i386 and none on x86-64: procps/powertop.c, networking/tls_sp_c32.c, tls_pstm_mul_comba.c, tls_pstm_sqr_comba.c (all `non-empty template ... not i386`) and tls_pstm_montgomery_reduce.c (`earlyclobber constraint \"=&d\" is not supported`, cparser.inc:7491). NOT a mis-gating problem that dropping a predefine would fix: pxx answers `__GNUC__=2` AND `__i386__` on i386, and the sources ask for exactly that pair -- `#if ALLOW_ASM && defined(__GNUC__) && defined(__i386__)` (tls_sp_c32.c:216) -- while powertop.c:500 is a bare `#ifdef __i386__` with no __GNUC__ gate at all. The source is selecting the arm we told it to select. The fix is to encode the template on i386, not to withdraw a claim."
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
