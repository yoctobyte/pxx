---
slug: bug-c-an-undeclared-identifier-in-a-file-scope-initializer-is-silent
track: C
type: bug
prio: 50
status: done
found: 2026-09-05
found-by: frankC
blocked-by: []
summary: "FIXED 2026-09-05 (frankC), same day it was found. An undeclared identifier in a FILE-SCOPE initializer used to produce no diagnostic at all and fold to 0 — four shapes mute, including `static const int f = O_NOFOLLOW;`, which is how eighteen crtl constants reached eleven busybox TUs as zero. Cause: CEvalConstPrimary set ONE flag for two populations — declared-but-not-constant (a VLA, which must keep working) and not-declared-at-all. FindSym separates them exactly, so the fix is a condition. The speculative-fold risk across 43 CEvalConstExpr call sites was settled both ways: the enum folder pre-scans and cannot reach the evaluator with an unresolved name, and a 625-file sweep (625 reached) produced a nonzero-exit set byte-identical to the baseline. Verified at fec9d034dc2b: gate.sh quick GREEN all 17 rows on the post-v404 tree, conformance 220/220, lua and sqlite build, cross i386/aarch64/arm32/riscv32, busybox 75 TUs byte-identical to the gcc oracle. AND THE POSITIVE CONTROL THAT FOUND IT NOW PASSES: an undeclared name injected into a real busybox TU at file scope refuses instead of exiting ok:, so the corpus zero is backed in both positions."
---

# The silent arm: file-scope initializers report nothing

Found by a POSITIVE CONTROL failing, not by a report. Busybox attempt six
counted `used as value` at 0 across 75 translation units; before trusting that
zero I injected a definitely-undeclared name into a real busybox TU and
recompiled with the harness's exact command line. At file scope it produced
**no output but `ok:`**. The zero was a true statement about a population the
instrument cannot see.

## The measurement (compiler `614ded15e88b`, x86-64)

```c
int a = NO_SUCH_A;                       /* silent */
int b = NO_SUCH_B + 1;                   /* silent */
int arr[3] = { NO_SUCH_C, 2, 3 };        /* silent — INTEGER aggregate element */
void *pt[2] = { NO_SUCH_D, 0 };          /* warns — pointer aggregate element  */
static int s = NO_SUCH_E;                /* silent */
struct S { int x; } st = { NO_SUCH_F };  /* warns */
int f(void) { static int ls = NO_SUCH_G; return ls; }  /* warns */
```

pxx reports **3 of 7**. `gcc -std=gnu99` errors on all 7.

## Where it is

`CEvalConstPrimary` (`compiler/cparser.inc`, the `tkIdent` arm). An identifier
that does not resolve sets `CConstExprSawNonConst := True` and contributes 0.

That flag conflates two different populations, which is why this reads as
deliberate:

- **declared but not constant** — `int arr[n]` is a VLA, and the flag is how
  the dimension reader learns to build one. Legitimate, must stay.
- **not declared at all** — `FindSym` returned < 0. Nobody wrote this; it is
  the mistake.

`FindSym(...) < 0` separates them exactly, so the fix is a condition, not a
redesign.

## Why it is prio 50 rather than folding into the sibling

The function-body arm was WRONG and LOUD — a warning, countable, and
`bb0c9c1ff` counted it: 18 crtl constants across 11 busybox TUs, found because
they warned. This arm is wrong and SILENT, so the same census returns 0 for it
whether it is clean or not. The constants ride in the same programs:
`static const int f = O_NOFOLLOW;` at file scope is exactly the shape, and
O_NOFOLLOW at 0 is a security guard switched off with no diagnostic anywhere.

## What has to be verified before it lands

`CEvalConstExpr` has 43 call sites. The one that needs establishing is whether
any caller parses SPECULATIVELY — saves `TokPos`, folds, and backtracks — since
`ErrorRecover` from inside a probe would report a mistake the program never
made. `CConsumeCastProcInit` does lookahead and is the first place to look.
Keep the `__`-prefix carve-out: it covers predefined-but-unmodelled
`__LINE__`/`__FILE__`/`__func__` and the `__builtin_*` surface, where a missing
name is our gap in a namespace the program does not own.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 3bfc63fef.
