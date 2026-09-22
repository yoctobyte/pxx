---
prio: 55
track: T
type: bug
found: 2026-09-22
found-by: frankb-8e
blocked-by: []
summary: "The harness has no channel for INSTRUMENT-UNAVAILABLE, so a probe that exits 2 specifically to say 'I could not measure' is published identically to a probe that exits 1 to say 'pxx is wrong'. tools/aarch64_cabi_prologue_probe.sh separates the two codes deliberately and documents why (exit 0 would be laundering, per done/bug-t-tstate-launders-skip-into-pass) -- and nothing downstream reads the distinction, so it arrived in a full tier as a cross-target compiler regression that cost a ticket and a bisect to discharge. THIS IS THE MIRROR of bug-t-a-recipe-that-self-skips-a-missing-oracle-is-not-counted-as-a-coverage-hole (p70), whose measured undercount is 'always DOWNWARD': an honest exit 0 loses a coverage hole, an honest exit 2 gains a false finding. ONE missing vocabulary, two directions. Do NOT fix it by making exit 2 quiet or by mapping it to SKIP -- a declared host limitation skips, a present-but-unusable instrument is undiagnosed, and the probe's own header rules both out."
---

# A probe that exits 2 to say its instrument is broken is published as a compiler red

**Residual from `bug-t-the-aarch64-srchash-job-has-been-red-since-d36af549ea5b-
with-no-ticket`, which `frankb-8e` closed as the missing host dependency
(`293c76699`).** *"Not a pxx defect"* is half a finding; this is the half with no
owner, routed here rather than left in a closed ticket's body.

## What happened, and it cost more than the bug

`tools/aarch64_cabi_prologue_probe.sh` exits **2** when `llvm-objdump` is absent
or unusable, printing *"INSTRUMENT failure — this is NOT a statement about pxx."*
in its own words. borg has no working `llvm-objdump`. The tier published the job
as RED, `twatch` tracked it as an open regression, and it took a ticket, a
three-measurement discharge and a bisect window to establish that **the compiler
was never implicated**: `b965f8633` changed zero files under `compiler/` or
`lib/`, and with `llvm-objdump-21` present the probe exits 0 with 5 signatures
agreeing with clang 21.1.8.

## It is the mirror of the p70 hole ticket, and that is the argument for fixing it once

`bug-t-a-recipe-that-self-skips-a-missing-oracle-is-not-counted-as-a-coverage-hole`
records 72 `NOT verified` sites that print an honest sentence and **exit 0**, so a
box missing a toolchain runs a narrower tier and reports an identical verdict. Its
measured conclusion is that *the undercount is always DOWNWARD*.

**That is true of the exit-0 spelling and it is not true of the channel.** The
same missing vocabulary, spelled exit 2, errs **upward**: it manufactures a
finding where there was none. A probe author choosing honesty picks between
laundering a pass and fabricating a regression, and both are the harness declining
to represent *"I could not measure."*

Sibling in the same group: `bug-t-a-recipe-cannot-declare-its-own-skip-a-coverage-
hole` (p45) — and `decide-t-should-a-skip-close-an-open-regression`, which is the
policy question this one's answer will touch.

## Three fixes, and two of them are wrong

1. **Install `llvm-objdump` on borg.** A host change, not a code fix, and it
   makes this instance green while leaving every future probe with the same
   choice. Worth doing and not sufficient.
2. **Make exit 2 quiet, or map it to SKIP.** *Rejected, and the probe's own
   header rejects it first*: an absent `clang` is a DECLARED host limitation and
   skips; a present-but-unusable instrument is UNDIAGNOSED, and exiting 0 is
   laundering (`done/bug-t-tstate-launders-skip-into-pass`). Mapping to SKIP also
   walks straight into the p70 ticket's undercount.
3. **Give the harness the third state.** `testmgr` classifies a job's exit code;
   teach it that **2 means INSTRUMENT-UNAVAILABLE**, publish it distinctly from a
   finding at 1 and from a SKIP at 0, and let `twatch` decline to open a
   regression on it. This is the one that generalises past this probe.

## The positive control this ticket already has

An earlier version of that gate checked only that the tool NAME was non-empty,
which `LLVM_OBJDUMP=/nonexistent` satisfies — and it printed a fabricated
`DISAGREEMENT — 5 pxx-side broken`. **A name standing in for the thing it names,
reproduced inside the guard written against it, within minutes.** So the exit-2
path is not defensive padding; it is the repair for a measured false finding, and
that is the reason option 2 destroys the row's value rather than merely quietening
it.

## Ranking

p55: it blocks nothing, and it has already cost one ticket, one bisect and one
open-regression slot in a fleet where an open regression is a dispatch target. It
rises if a second probe exits 2 — at which point the cost is per-probe and
recurring rather than one row.

## 2026-09-22 (frankb-8e) — measured, and it CORRECTS my own sentence: a skip code already exists (77)

I gave frankz-e5 "nothing downstream reads the distinction" in a message as an
assertion. Measuring it produced a better answer than the assertion and a worse
one for the assertion.

**What is true:** `testmgr.py` — which is what publishes the tstate verdict —
tests `returncode` against **zero only**, ~21 sites, and honours no other code.
`twatch.py` likewise (6 sites). So a probe's exit 2 reaches the report as a
plain failure and is attributed to a code range, which is this ticket.

**What is FALSE, and it was my sentence:** I wrote that there is "no exit-code
vocabulary above pass/fail anywhere in the harness". There is.
**`tools/gate.sh:104` special-cases exit 77** — the autotools SKIP code —
for `tools/selfhost_fixedpoint.sh`, whose own "no pinned stable to seed from"
condition uses it, and gate.sh prints `SKIP: ...` and returns 0.

**How I got it wrong is the part worth keeping, because it is this repo's own
rule and I hit it while writing a negative result.** My grep was
`returncode|rc|exitcode [=!]= 2` over `testmgr.py`, `gate.sh` and `twatch.py`.
It answered 0 for all three and I read three zeroes as three answers. **The
positive control is what exposed it**: the same pattern with `2` replaced by `0`
matches 21 and 6 times in the two Python files and **ZERO times in `gate.sh`** —
because `gate.sh` is shell and never contains the word `returncode`. The control
fired for the files the pattern could see and stayed silent for the one it could
not, so the instrument printed a confident negative about a file it was blind
to. One grep in shell idiom (`rc=$?`, `[ "$rc" = N ]`) found 77 immediately.

**THE CONSEQUENCE FOR THIS TICKET'S REMEDY, which is now cheaper and also
trickier than "build a channel":**

- A skip convention EXISTS and is in live use (77, one producer, one consumer).
- `gate.sh` honours it; **`testmgr.py` does not** — no `77` anywhere in it.
- **But 77 maps to `return 0`, a PASS**, which is exactly what this probe's
  design refuses: a broken instrument laundered into a pass. So adopting 77 as
  written would re-introduce `done/bug-t-tstate-launders-skip-into-pass`.

So the missing state is not "skip" — that exists — it is **skip AND count as a
coverage hole**, which is precisely what the p70 neighbour says `skip_holes`
cannot express. The two tickets want the SAME new state from opposite sides,
and whoever takes either should read the other first rather than adding a third
spelling. Do not re-semantic 77 casually: `selfhost_fixedpoint.sh` depends on
its current meaning.

**And the mirror reading is correct as e5 states it, with one scoping note.**
The p70 row's "the undercount is always DOWNWARD" is about COUNTING HOLES — a
self-skip exits 0 and is not counted, so `skip_holes` reads low. This probe is
not undercounted as a hole; it is **overcounted as a finding**. Different
errors, not a contradiction: the p70 sentence is scoped to the exit-0 spelling,
exactly as e5 wrote it, while the missing channel errs in both directions.
