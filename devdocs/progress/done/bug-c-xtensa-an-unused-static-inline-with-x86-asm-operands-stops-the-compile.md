---
slug: bug-c-xtensa-an-unused-static-inline-with-x86-asm-operands-stops-the-compile
title: "xtensa: an unused static inline whose asm OPERANDS this frontend cannot bind stopped the compile"
track: C
type: bug
prio: 35
status: done
owner: claude-dupwt
found: 2026-11-20
found-by: claude-dupwt (Rainyday docs/tickets/open/0004: 13 of 60 portable files stop only on x86 asm in unused static inlines; rump-pxx g20)
---

# xtensa: unused static inline with x86 asm operands

## Before

Since the g20 fix, an instruction the Xtensa text engine lacks POISONS a
`static` routine or a header routine instead of stopping the compile: a call
to it refuses, and an uncalled one costs nothing, as with gcc, which never
expands it. The OPERAND checks in CAsmBuildBlockXtensa still ended in Error().
Those are: a constraint other than a/r/g/rm/i/n (x86's "=m"), a clobber or
register variable it cannot honour, a float or too-wide operand, a bad %N or
%[name], an operand modifier. They run first, so x86 helpers such as

    static inline unsigned short g(void)
    { unsigned short w; __asm__ volatile("fnstcw %0" : "=m"(w)); return w; }

stopped an `--target=xtensa --freestanding` compile that never called them
(latest-96a40f3302: `constraint "=m" is not supported`). x86-64 already
passes the same file.

## Now

Each of those 14 refusals goes through CXtAsmRefuse. In a routine
CAsmMayPoison allows (static, or in a header), that poisons the routine with
the refusal's text and returns an empty block. Anywhere else it stops the
compile with the same message as before. A call to the poisoned routine
refuses: `cannot call g: its inline asm cannot be built for xtensa (C: xtensa
inline asm constraint "=m" is not supported ...)`.

## Rows

tools/check_casm_xtensa.sh (test-core, beside the unknown-instruction rows)
covers three cases: an unused static inline with `"=m"` compiles; a call to it
refuses by name; a non-static routine with it still stops at the constraint.

## Not measured

Rainyday's 60-file micro-profile pass has no script in its tree, so the
"9 of 60" there is not re-measured. The 13 files it attributes to unused
static inlines may also stop on other things.

Verified: gate quick GREEN; tools/check_casm_xtensa.sh OK.
