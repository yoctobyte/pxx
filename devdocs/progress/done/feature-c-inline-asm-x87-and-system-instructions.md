---
track: C
tags: [c, inline-asm, assembler, x86-64, rump, netbsd]
prio: 20
type: feature
blocked-by: []
summary: "NetBSD's x86 cpufunc.h assembles: fnclex/fclex/finit/fwait, fnstcw/fstcw/fldcw, fnstsw/fstsw (memory and %ax), fnstenv/fldenv, fnsave/fsave/frstor, clts/invd/wbinvd, rdpmc, monitor/mwait, pushfq/popfq, lldt; and `\"=m\" (*(char (*)[N])p)` is no longer refused as a side effect."
status: done
owner: claude-dupwt
---

# The x87 and system instructions of NetBSD's cpufunc.h (rump row 1)

The rump re-measure at 6ee4a858b8 (nilix docs/rump-pxx, repro g26) had 204
of 488 files stop at the first of these. `cpufunc.h` defines them as static
inlines, and pxx assembles a template even when nothing calls it, so every
file that includes `<machine/cpufunc.h>` stopped.

## What was missing

1. **Mnemonics**, now in `AsmSystemOp` (asmenc.inc) and, for the ones that take
   an operand, in the AT&T base list (asmatt.inc):
   - zero-operand: fnclex `DB E2`, fclex/finit (with the `9B` fwait),
     fwait/wait `9B`, clts `0F 06`, invd `0F 08`, wbinvd `0F 09`, rdpmc
     `0F 33`, monitor `0F 01 C8`, mwait `0F 01 C9`, pushf(q) `9C`, popf(q) `9D`;
   - x87 memory ops: fnstcw `D9 /7`, fldcw `D9 /5`, fnstenv `D9 /6`, fldenv
     `D9 /4`, fnstsw `DD /7` (and `DF E0` for `%ax`), fnsave `DD /6`, frstor
     `DD /4`, plus the fwait-prefixed fstcw/fstenv/fstsw/fsave;
   - lldt `0F 00 /2`, the sibling of ltr.
   These match gcc's bytes for every form the probe compiled.
2. **`"=m" (*(char (*)[512])area)` was refused** as "output operand has a side
   effect". This blocked fxsave, fxsave64, xsave, xsaveopt and fnsave, although
   every encoder already existed. A cast to a pointer-to-array is built as
   `(t = e, t)` with a hidden temp, and `CAsmExprIsPure` refused the
   assignment. Storing a pure e into a temp nobody else names is unobservable,
   so that exact shape now counts as pure.

Fixing (2) exposed a silent miscompile, recorded separately as
[[bug-c-an-m-input-of-a-pointer-to-array-deref-reads-the-pointer]].

`test/c_inline_asm_x87_and_system.c` runs the user-mode-safe part (control word,
status word, fnsave/frstor and fxsave/fxrstor round trips, pushfq/popfq) and
matches gcc at -O0 and -O2. The privileged instructions only have to
assemble; the test holds them in uncalled static inlines, as cpufunc.h does.
