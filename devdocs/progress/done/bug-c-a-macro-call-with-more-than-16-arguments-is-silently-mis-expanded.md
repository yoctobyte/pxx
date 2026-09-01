---
slug: bug-c-a-macro-call-with-more-than-16-arguments-is-silently-mis-expanded
title: "A macro call with more than 16 arguments was mis-expanded with no diagnostic, and could hang the compiler"
track: C
prio: 70
type: bug
status: done
created: 2026-09-02
found-by: frankD
owner: frankD
blocked-by: []
summary: "FIXED 2026-09-02. The C preprocessor reserved SIXTEEN argument slots per expansion level (a stride, not the array size: MAX_CPREP_ARGS is 4096). Past sixteen the comma stopped being a separator, so the remaining arguments fused into the last one and the expansion came out malformed with no diagnostic. C99 5.2.4.1 requires at least 127. Found by attempting a 79-applet busybox userland: coreutils/factor.c calls a 20-argument macro from inside another 20-argument macro and the compiler NEVER RETURNED -- 8 minutes, no output. Stride raised to 128 and the overflow is now an error instead of a silent truncation."
---

# Sixteen was the stride, not the limit anyone chose

`MAX_CPREP_ARGS` is 4096 and reads like the limit. It is not: `CPArgStart` /
`CPArgEnd` are sliced `argBase := level * 16`, and three separate loops capped
splitting at `argc < 16`. So the real limit was **sixteen arguments per macro
invocation**, and it lived in an anonymous `16` in three places.

C99 5.2.4.1 puts the conforming minimum at **127**.

## What it looked like

Silent, then loud in the wrong place, then not at all:

| shape | what happened |
| --- | --- |
| 16 arguments | correct |
| 17 arguments, simple body | `error: stray token at top level: 'G'` |
| 20 arguments nested inside another 20 | **compiler never returns** |

The third is `coreutils/factor.c`'s `packed_wheel` table — `P(...)` expanding
to `R(...)`, twenty arguments each — and it is how this was found. It was the
only HANG among 148 translation units; the other 133 compiled and 14 failed on
named crtl gaps.

Past the cap the comma was simply not treated as a separator. The arguments
after the sixteenth fused into the sixteenth, so the body substituted a
parameter with a token sequence that still contained commas and parentheses.
Nothing checked, nothing reported.

## The fix

- `CPREP_ARGS_PER_LEVEL = 128`, named in `defs.inc` beside `MAX_CPREP_ARGS`
  with the arithmetic that keeps them consistent: the deepest expansion level
  is 16 (`CPTempStr16`), so 17 × 128 = 2176 fits inside 4096.
- The three anonymous `16`s become that constant.
- **Overflow is now an `Error`, not a truncation.** A cap that silently changes
  the meaning of the program is the shape this whole class comes from; a cap
  that says so is a limit.

## Verified

Against gcc, same source, both compilers: 16, 17, 20, 40 and 127 arguments all
agree (`136 / 153 / 210 / 820 / 8128`), and factor.c's own two-row table comes
out `735435177334091028 635800628644997282` on both.

`test/c_macro_many_args.c` carries all of it. **Positive control: the pinned
compiler HANGS on that file** (`timeout` exit 124), so the row cannot pass by
accident.

`tools/gate.sh quick` GREEN with the FPC seed canary concurrent.
