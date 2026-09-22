---
prio: 40
track: A
summary: "ANY `PRINT` IN A BASIC PROGRAM REFUSES ON riscv32 AND xtensa -- `compiler error: PXXWriteDecW not found` -- so the BASIC frontend cannot produce output at all on those two targets. Measured 2026-09-22 at binary 81bf5f94fb6f, one row per target: `10 LET A = 7 / 20 PRINT A` and `10 PRINT \"hi\"` both BREAK on riscv32 and xtensa and build on arm32, aarch64, i386 and x86-64; a BASIC program with no PRINT builds on all six, which is the row that says this is about the write path and not about the frontend generally. PRE-EXISTING, NOT A REGRESSION, AND THE CONTROL IS THE REASON THAT SENTENCE IS HERE: the PINNED compiler refuses identically on both targets, so this is not 523833fde (the needsAnsiRuntime evidence scan) even though bparser.inc's own comment records that commit retiring the flag BASIC used to ride on. CAUSE, from a two-file census and not a guess: riscv32 routes EVERY ordinal write through builtinheap's PXXWriteDecW and xtensa reaches it the same way -- the mechanism `TargetCodegenCallsHeapRuntime` (emit.inc) owns and names -- and `compiler/bparser.inc` NEVER CALLS `PullTargetRuntimeUnits`, which is the one routine that pulls builtinheap for a driver whose language has no `uses` clause to say so. Every other skeleton frontend calls it: fparser.inc:388, aparser.inc:389, gparser.inc:402, zparser.inc:2063. BASIC is the only one of the five that does not, and it is a ONE-LINE call in the same position. THE ONE-LINE FIX IS NOT OBVIOUSLY SAFE AND THAT IS WHY THIS IS A TICKET: `BSourceUsesAUnit` (bparser.inc:710) decides whether the AnsiString shims may be emitted, and its stated contract is that `will builtinheap be here` and `does this source say USES` are THE SAME QUESTION for BASIC. Pulling builtinheap ambiently makes the first true while the second stays false, so the two stop being the same question and that function's premise -- which its own comment argues at length and tells you not to replace -- becomes stale. Whoever fixes this must say what `BSourceUsesAUnit` means afterwards, in that comment, in the same commit."
status: backlog
owner: unassigned
---

# A BASIC program cannot print anything on riscv32 or xtensa

- **Type:** bug (frontend × target runtime injection) — Track A, tag S
- **Status:** backlog — filed 2026-09-22 by frankb-8e, found by applying the
  sibling rule to an unrelated fix, not by a test

## The measurement

Binary `81bf5f94fb6f`, `--platform=posix`, one row per target. Every cell is a
build, not an inference.

| source | riscv32 | xtensa | arm32 | aarch64 | i386 | x86-64 |
| --- | --- | --- | --- | --- | --- | --- |
| `10 LET A = 7` / `20 PRINT A` | **BREAK** | **BREAK** | ok | ok | ok | ok |
| `10 PRINT "hi"` | **BREAK** | **BREAK** | ok | ok | ok | ok |
| `10 LET A = 7` / `20 IF A = 0 THEN END` (no PRINT) | ok | ok | ok | ok | ok | ok |

`compiler error: PXXWriteDecW not found`. The third row is the one that keeps
this narrow: the frontend is fine on those targets until it writes.

## Pre-existing, and the control is why that is stated rather than assumed

The pinned compiler refuses identically on both targets. So this is **not**
`523833fde` (the `needsAnsiRuntime` evidence scan), even though
`bparser.inc:731` records that commit retiring the unconditional flag BASIC
used to ride on — which is exactly the story a reader would construct, and it
is wrong. One pinned-versus-HEAD run settles it, and CLAUDE.md's rule is to
attribute a delta to a RANGE before attributing it to yourself.

## Cause

`TargetCodegenCallsHeapRuntime` (`emit.inc:1705`) owns the target set and names
both mechanisms: riscv32 routes **every** ordinal write through
builtinheap's `PXXWriteDecW`, and the aggregate-result epilogue lowers onto
`PXXMemMove` on aarch64/arm32/riscv32/xtensa. `PullTargetRuntimeUnits`
(`frontend_prologue.inc:162`) is the one routine that pulls builtinheap for a
driver whose language has no `uses` clause to say so.

**`compiler/bparser.inc` never calls it.** Every other skeleton frontend does:

| frontend | call site |
| --- | --- |
| Fortran | `fparser.inc:388` |
| Ada / Algol | `aparser.inc:389` |
| (g) | `gparser.inc:402` |
| Zig | `zparser.inc:2063` |
| **BASIC** | **absent** |

Five drivers, one missing, and the routine's own header says it exists because
the block had reached three identical copies — so this is a driver that was
never wired to the fix rather than one that regressed out of it.

## Why the one-line call is not obviously the fix

`BSourceUsesAUnit` (`bparser.inc:710`) decides whether the AnsiString shims may
be emitted, and its contract is explicit:

> BASIC pulls builtinheap through exactly one door — `USES <unit>` during the
> parse — so "will builtinheap be here" and "does this source say USES" are the
> SAME question, and it is the only honest predicate for whether the shims can
> be emitted.

`PullTargetRuntimeUnits` calls `ParseUsesUnitAmbient('builtinheap')`, which
adds no `tkUses` token — so on riscv32 and xtensa builtinheap **would** be
present while `BSourceUsesAUnit` still answers False. The two stop being the
same question on exactly the two targets this ticket is about, and that
function's comment argues its premise at length and ends *"Do not replace this
scan with that flag"*.

That is a live contradiction, not a style point: the predicate would be a
FALSE NEGATIVE there (shims withheld although the bodies arrived), which costs
nothing today and is a trap the next person steps in.

**So the acceptance is not "PRINT compiles".** It is: `PRINT` builds and RUNS
on riscv32 (qemu is available for it; xtensa has no runner here, so say that
rather than claiming it), a BASIC program with no `PRINT` still pulls nothing
on those targets, and `BSourceUsesAUnit`'s comment says what it means
afterwards — in the same commit, because a premise falsified silently is how
this class survives.

## How it was found

Applying *"fixed one arm of a double case? grep for the sibling"* after
`23fcd326f` (the Pascal record/`PXXMemMove` break). The sibling search was for
other frontends that could reach a builtinheap routine without saying so, and
it turned up a third instance of the class — the first being
`bug-a-cfront-riscv32-byval-record-result-pxxmemmove` (C, done, p70, rooted an
18-job cascade), the second the Pascal record arm. Three frontends, three
causes, one shape, which is the argument for
[[feature-a-pull-builtinheap-on-demand-instead-of-predicting-it]] rather than a
fourth prediction site.
