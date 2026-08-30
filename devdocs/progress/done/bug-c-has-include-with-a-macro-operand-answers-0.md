---
prio: 35
track: C
type: bug
blocked-by: []
summary: "`__has_include(HDR)` where HDR is a macro expanding to `<stdio.h>` answers 0 under pxx and 1 under gcc. Same silent shape as the pdfgen endian bug it was found beside: no error, no warning, the guarded #include is simply skipped and whatever the header would have defined stays undefined. The literal forms `__has_include(<x>)` and `__has_include(\"x\")` are correct; only a macro-expanded operand is affected."
status: done
owner: frankC
---

# `__has_include(MACRO)` answers 0 where gcc answers 1

## Measured at `5ced3d9a0`

```c
#define HDR <stdio.h>
#if __has_include(HDR)
  ...
#endif
```

| form | gcc | pxx |
| --- | --- | --- |
| `__has_include(<stdio.h>)` | 1 | 1 |
| `__has_include("relative.h")` | 1 | 1 |
| `__has_include(<a>) && __has_include(<b>)` | 1 | 1 |
| `!__has_include(<missing>)` | 1 | 1 |
| `__has_include(<x>) ? 7 : 9` | 7 | 7 |
| **`__has_include(HDR)`, HDR a macro** | **1** | **0** |

One divergence of six. Not an error and not a warning: the guarded `#include`
is skipped, and whatever that header would have defined stays undefined —
which, in `#if`, is 0. Exactly the shape of
`bug-c-has-include-unsupported-so-pdfgen-selects-big-endian`, beside which this
was found.

## Why it is filed as a bug and not as compat

By CLAUDE.md's table this looks like "gcc accepts a form we reject", which is
compat, ranked by how much real code uses it. It is not: we do not *reject* it,
we answer it **wrongly and silently**, and a program that guards a real
`#include` on it compiles clean and behaves differently. That is the
silent-wrong-behaviour escape, so it takes a `bug-` slug in the owning lane.

The prio is low because the *reach* is genuinely small, not because the class
is: nothing in this repo's C corpora writes a macro-expanded operand — pdfgen,
zlib, lua and sqlite all use the literal forms, which are correct.

## Cause, and it is deliberate-but-incomplete

`CPExprHasInclude` (`compiler/cpreproc.inc`) parses the operand itself and
accepts only a `<`- or `"`-introduced header-name, because that is the shape
the C standard defines and the shape ordinary macro expansion cannot survive
(`<stdio.h>` is a `<`, an identifier, a `.`, an identifier and a `>` — division
and comparison around a macro-expandable `stdio`). Anything else consumes to
the closing paren and answers 0, which is documented in the function's comment
as a known blind spot.

The correct handling is the one the standard describes: if the operand does not
already look like a header-name, macro-expand it *first*, then re-parse the
result as a header-name. The machinery for that expansion already exists in
this file (`CPExpandRangeForLevel` and friends, used by the function-macro arm
of `CPExprAtom`).

## What a fix must assert

- the six rows above all match gcc
- `#define HDR "relative.h"` — the quoted form through a macro too
- a macro that expands to something that is *not* a header-name still answers 0
  rather than erroring or looping
- the existing literal forms are unchanged (`test/chas_include.c`)

## Log
- 2026-08-30 — found by frankC while implementing `__has_include`
  (`bug-c-has-include-unsupported-so-pdfgen-selects-big-endian`), measured
  against gcc on the same file, and filed rather than folded in: the fix is a
  different mechanism (macro expansion of the operand) from the one that
  ticket needed, and it deserves its own assertions.

## Fixed. frankC, 2026-08-30

`CPExprHasInclude` now does what C23 6.10.1 describes: when the operand is not
*already* a header-name, macro-expand it and re-read the result as one.

| form | gcc | pinned `53800fbeb0b6` | now |
| --- | --- | --- | --- |
| `__has_include(HDR)`, `HDR` = `<stdio.h>` | 1 | **0** | 1 |
| `__has_include(QHDR)`, `QHDR` = `"rel.h"` | 1 | **0** | 1 |
| `__has_include(NOPE)`, missing header | 0 | 0 | 0 |
| `__has_include(HDR) && !__has_include(NOPE)` | 1 | **0** | 1 |
| the five literal forms | — | correct | unchanged |

`test/chas_include.c` run through pxx and through gcc is **byte-identical, all
seven lines** — the file was kept gcc-compilable specifically so it can be an
oracle target (`tools/gcc_diff_probe.sh`).

### The two halves of the rule point opposite ways, and both are in the same paragraph

The operator must **not** be reached *by* expansion — `<endian.h>` is not a token
sequence ordinary macro rules survive — and its operand **must** be expanded
*when it is not already a header-name*. The function's comment used to record the
first as the reason the second was impossible. It is the reason the second has to
be done by hand, which is not the same thing.

### One reader for both operand shapes

`CPHeaderNameOf` parses `<x>` / `"x"` out of a string, and both the literal path
and the expanded path go through it. A header-name that works spelled out is the
same header-name when a macro produced it, and keeping that in one function is
the entire content of the fix; two readers would have drifted on the first edge
case (leading space, missing closer).

Expansion runs at **arg level 0**, which is free by construction rather than by
luck: the arg buffers are indexed by the expander's own recursion level, and
that level is ≥1 for every call the normal path makes
(`CPExpandRangeForLevel` passes `level + 1`).

### A divergence found by asking the oracle, and kept

gcc **rejects** an operand that does not expand to a header-name —
`error: operator '__has_include' requires a header-name`. This ticket's own
"what a fix must assert" said such an operand should *answer 0 rather than
erroring*; that was written before anyone asked gcc. Measured, gcc errors.

Kept lax, and it is the compat table's *"we accept a form the reference
rejects"* row: **no program gcc accepts can observe the difference**, because
gcc refuses to compile every program containing one. Not a defect, and not
error-reporting parity worth chasing.

It is **asserted** rather than merely allowed, in `test/chas_include_lax.c`:
"answers 0", "errors" and "loops forever" are indistinguishable from a test that
never runs it, and the operand now goes through the macro expander, which is
exactly where a loop would live. Its second row is an operand that *starts* like
a header-name and never closes (`<stdio.h`), which is the case where a sloppy
reader would run to the end of the buffer and call it a name.

Split into its own file so `chas_include.c` stays gcc-compilable — a test that
can be diffed against the oracle is worth more than one assertion's worth of
tidiness.

### Gate

`make compiler/pascal26` — converged, 1 round, `6c337931e11c`. Six-row gcc
differential agrees. `chas_include` (7 lines) and `chas_include_lax` green;
malformed operands terminate, no loop, no error.
- 2026-08-30 — resolved, commit 7f08c6798.
