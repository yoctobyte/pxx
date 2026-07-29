---
track: C
prio: 55
type: bug
---

# `-g` on a C file gives line numbers from the PREPROCESSED text

**FIXED 2026-07-29 (`ee6ef36ac`).** All three parts landed together, and the
dependency below turned out to be the cheap half:

1. cpreproc emits gcc-style `# <line> "<path>"` markers, DRIFT-based (only when
   the origin would otherwise be inferred wrongly), `-g` only.
2. Headers became real files in the line table. The multi-file CU support this
   ticket said it depended on had landed for NilPy meanwhile; what it still
   needed was generalising RANGES — a NilPy import is one contiguous run, a C
   header's tokens interleave at every `#include` boundary — so files and ranges
   are now separate tables and `AllocNode` consults ranges before the
   `DbgMainTokEnd` test.
3. Physical-line accounting: `CPReadLine` splices `\`-continued lines internally
   and consumed those newlines silently, so a 4-line `#define` counted as one.

`break addup` -> `dbgc.c:4` (was 2068); `break strlen` -> `string.c:72`.
Breakpoint lines match gcc EXACTLY; `info line <func>` still differs by one
because gcc emits a prologue row at the `{` and we start at the first statement
— where a function's first row sits, not a mapping error.

```sh
compiler/pascal26 -g prog.c out    # prog.c is 18 lines
gdb ./out
(gdb) break addup
Breakpoint 1 at 0x42bf25: file dbgc.c, line 2068
```

Everything else works — breakpoints resolve, `info args` and `info locals` are
right, stepping and `print` work (fixed alongside the NilPy DWARF work). Only
the LINE numbers are wrong, and they are wrong in a specific way: `CPreprocess`
rewrites `Source` in place with every `#include` inlined and every macro
expanded, and the lexer then numbers lines in THAT buffer. Line 2068 is a real
line — of the preprocessed text, most of which came from `stdio.h`.

Rust and Zig do not have this (no preprocessor); their `-g` lines are correct.

## What it needs

`compiler/cpreproc.inc` keeps **no line information at all** — no `#line`
emission, no origin map (`grep -c 'LineMap\|#line' compiler/cpreproc.inc` = 0).
So this is not a one-liner:

1. Track (origin file, origin line) per emitted character or per emitted line
   in `CPrepOut`, across `#include` nesting and multi-line macro expansion.
2. Have `CLexAll` stamp the ORIGIN line on each token instead of the position
   in the preprocessed buffer.
3. **Depends on multi-file CU support.** Headers are inlined, so once the map
   is right the tokens legitimately come from several files, and the Tier 1
   line table describes exactly one (`DbgMainTokEnd` gives every non-main-file
   token line 0). Without step 3 a correct map would just move the wrongness
   around: header code would report line 0 rather than a plausible wrong line.

Step 3 is the same work an imported-`.py` breakpoint needs, so the two should
be done together — see [[feature-debuggability-umbrella]] and
`devdocs/dev/dwarf.md`.

## Worth noting

The failure mode is the one this project keeps paying for: not an error, a
*plausible wrong answer*. `dbgc.c:2068` looks like a real location, and in a
file with 2000+ preprocessed lines you would not immediately notice it is the
wrong 2068.

## Repro / gate

```c
#include <stdio.h>
static int addup(int a, int b) { int s = a + b; s = s * 2; return s; }
int main(void) { printf("r=%d\n", addup(3, 4)); return 0; }
```

`gdb -batch -ex 'break addup' -ex run -ex bt ./out` must name the line in the
ORIGINAL file.

## Log
- 2026-07-29 — resolved, commit ee6ef36ac.
