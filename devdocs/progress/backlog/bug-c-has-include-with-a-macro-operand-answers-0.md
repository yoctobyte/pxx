---
prio: 35
track: C
type: bug
blocked-by: []
summary: "`__has_include(HDR)` where HDR is a macro expanding to `<stdio.h>` answers 0 under pxx and 1 under gcc. Same silent shape as the pdfgen endian bug it was found beside: no error, no warning, the guarded #include is simply skipped and whatever the header would have defined stays undefined. The literal forms `__has_include(<x>)` and `__has_include(\"x\")` are correct; only a macro-expanded operand is affected."
status: new
owner: ""
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
