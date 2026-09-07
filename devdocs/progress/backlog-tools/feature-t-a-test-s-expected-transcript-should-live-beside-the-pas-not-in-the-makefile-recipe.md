---
prio: 50
track: T
type: feature
status: backlog
summary: "A whole-transcript test's expected output lives in an inline printf inside a 12000-line Makefile, so EXTENDING THE TEST LOOKS COMPLETE FROM INSIDE THE TEST -- you add rows to the .pas, the .pas is self-consistent and its own comments agree, and the assertion it is judged by is in a file you never opened. That is what cost 18 hours of RED on the native tier (2ba37ba91 added rows j..n; the printf still said a..i). Proposal: let a `.expected` file beside the .pas be the default source, as several tests already do, and keep the inline printf only where the transcript is target-dependent. NOT started -- filed at frankuser's suggestion and explicitly not to be done without asking, since it touches many recipes."
---

# A test's expected transcript should live beside the .pas, not in the recipe

## The failure it removes

`test/test_sizeof_user_name_shadows_builtin.pas` gained five printed rows in
`2ba37ba91`. The Makefile's inline `printf` at what is now `Makefile:12669`
still listed rows `a..i`. Nothing compiled wrong — every added row matches the
source's own comment and the file's own `Halt(chk)` self-check passes with exit
0 — but `expect_same` compares WHOLE transcripts, so five unasserted rows made
the job RED rather than merely weaker.

**The shape is the point, and it is not carelessness.** Eight lines below the
last new row, that same file says *"ASSERT, do not only PRINT"* — written by
the same commit that added rows the recipe did not know about. The author of
that sentence walked into the trap while stating the rule, because **the
assertion for this job does not live in the file being edited.** From inside
the `.pas`, adding a row and a matching self-check looks like the complete job.

## What it cost, which is the argument for the prio

Native came back RED at every sha from 2026-09-02T16:09Z for about eighteen
hours and a dozen tstate commits, for this and nothing else. STILL-RED is
listed separately from NEW-RED precisely so that is survivable, and it was.
**What it cost was discrimination: a red left standing because it is understood
looks, at a glance, exactly like one nobody has read.**

## Proposal

Prefer a `.expected` beside the `.pas` — the convention several tests already
use — so the two halves of a test sit in one directory and an editor sees both.
Keep the inline `printf` only where the transcript is genuinely target-dependent
(this file's own row `h` prints `SizeOf(Pointer)`, which is why it has no
`.expected` today; that is a reason to make the file target-independent, not a
reason to keep the assertion in the recipe).

**Not started, and deliberately so.** Filed at frankuser's suggestion with the
explicit note that it should not be done without asking first — it touches many
recipes at once, and a sweeping edit to `Makefile` is the change most likely to
collide with whatever lane is mid-overhaul.

[[regression-test-core-test-sizeof-user-name-shadows-builtin]]

## A SECOND DATED INSTANCE, and it is a COUNT rather than a transcript (frank-subcoord, 2026-09-07)

`lib_sysutils_delphi_exceptions.pas` gained assertions. The recipe judges it with

```make
tools/expect_same.sh lib_sysutils_delphi_exc.1 "$$(/tmp/lib_sysutils_delphi_exc | grep -c '=ok')" "21"
```

so the program printed **25** `=ok` lines against a literal `21` in the Makefile.
Fixed at `b2af9952b`. Same failure as `2ba37ba91`: **the .pas was self-consistent
and complete from inside itself, and the number it is judged by is in a file the
author never opened.** Seen again from the other side an hour later — a full tier
run at `594cfda54ef2` (a sha predating the fix) reported it as its ONLY red,
which is the reproduction behaving correctly and is how the instance was
re-noticed.

**Why this instance is worth adding rather than just incrementing a count: it is
not a transcript.** The ticket's proposal is a `.expected` file holding expected
OUTPUT, and this row asserts a **derived scalar** — `grep -c` of a marker. A
`.expected` file still fixes it (the count moves beside the .pas, so adding a row
and updating the expectation are the same edit in the same directory), but a
proposal written only around transcripts could easily be implemented in a way
that leaves count-shaped rows in the recipe. **Both shapes have the identical
coupling and the fix must cover both.**

A third shape exists in the same family and is worth naming while the pattern is
in view: an expectation that is a COUNT is strictly worse than one that is a
transcript, because a count cannot say WHICH row appeared or vanished. `21` vs
`25` tells you four assertions moved and nothing about which, whereas a
transcript diff names them. So where a row can reasonably be a transcript,
that is the better target for this work, not merely the easier one.

**Frequency, since prioritisation needs it:** two instances in 18 days that we
know of (`2ba37ba91`, 18h of native RED; `b2af9952b`), both found by a red rather
than by review, and both invisible to the author at the moment of the edit.
