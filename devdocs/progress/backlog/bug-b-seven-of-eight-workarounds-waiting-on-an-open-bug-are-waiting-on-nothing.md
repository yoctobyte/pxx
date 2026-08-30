---
track: B
prio: 35
type: bug
status: backlog
found: 2026-08-30
found-by: frankD
blocked-by: []
summary: "track-b-workarounds.md's section titled 'Waiting on an open bug' has 8 rows and 7 cite a bug that is now in done/ or rejected/. Four of those seven carry no keep-note, so lib/rtl and lib/pcl are written non-idiomatically for bugs fixed weeks ago -- verified live in the code, not just stale in the ledger. The file's own instruction ('when the listed bug moves to done/, revert the workaround and drop the entry') has not been run, and the section header asserts the opposite of what is true."
---

# Seven of eight "waiting on an open bug" workarounds are waiting on nothing

Found by frankD during the `devdocs/dev/**` live-reference audit, measured at
`76d281418`. **Read-only; I did not edit the ledger or `lib/**`** — the file is
Track B's and so is the code.

## The measurement

`devdocs/dev/track-b-workarounds.md` opens with its own lifecycle rule:

> When the listed bug moves to `devdocs/progress/done/`, revert the workaround
> here and drop the entry. **Verify the bug ticket is still in
> `backlog/`/`blocked/` before assuming the workaround is still needed.**

That check has not been run. Every ticket cited in the section headed
**"Waiting on an open bug"**:

| # | site | blocking ticket | state |
| --- | --- | --- | --- |
| 1 | `lib/rtl/math.pas` (`DdFloor`, `DdRint`) | `bug-a-int-of-a-large-double-saturates-to-32-bit-on-i386-and-arm32` | **done** |
| 2 | `lib/rtl/bignum.pas`, `examples/bignum/bigmath.pas` | `bug-managed-record-result-self-arg` | **done** |
| 3 | `lib/rtl/chacha20poly1305.pas` | same | **done** — row says keep anyway |
| 4 | `lib/rtl/aesgcm.pas` (`BlkCopy`) | `bug-fixed-array-assignment-no-copy` | **done** — row says do not revert yet |
| 5 | `lib/pcl/mimic_reportlab_pdfgen.pas` | `bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory` | **done** |
| 6 | `lib/rtl/ed25519.pas` | `bug-aggregate-member-array-as-var-param` | **done** |
| 7 | `lib/rtl/math.pas` (`SinCosFast`) | `bug-a-i386-var-float-parameter-faults-on-first-access` | **done** — row says the record is the shape to keep |
| 8 | `lib/rtl/mimic_collections_abc.py` | `bug-n-keys-through-an-untyped-receiver-is-not-dispatched-cross-module` | **backlog** — correctly placed |

**One row of eight is in the right section.** Rows 3, 4 and 7 already carry a
reason to keep the code as-is, so they are not revert candidates — but they are
also not "waiting on an open bug", and three of them being parked under that
heading is part of why nobody re-checked the other four.

Reproduce:

```
grep -o '\[\[[a-z][^]]*\]\]' devdocs/dev/track-b-workarounds.md |
  tr -d '[]' | sort -u |
  while read s; do echo "$s -> $(ls -d devdocs/progress/*/$s.md 2>/dev/null |
    sed 's|devdocs/progress/||;s|/.*||' | tr '\n' ' ')"; done
```

## This is code debt, not a stale document

Checked before filing, because "the ledger is out of date" and "the library is
carrying dead workarounds" are different tickets and only the second is worth
prio:

- `lib/rtl/math.pas:702` and `:1216` still read `Double(Trunc(x))` where `Int(x)`
  is the natural spelling — row 1's workaround, live.
- `lib/rtl/ed25519.pas` still has no `TPoint`; the four field coordinates are
  still four standalone `TGf` vars — row 6's workaround, live.

I did not check rows 2 and 5 in the source. Whoever takes this should, because
the count that matters is how many reverts are actually available, not how many
rows are misfiled.

## The work

For rows 1, 2, 5 and 6: attempt the revert against `$(PXX_STABLE)`, run
`make lib-test`, and either drop the entry or move it to the **Cleanup backlog**
section with a measured reason it still cannot be reverted — which is exactly
what row 4 does well, and what makes row 4 the model rather than a problem.

**Reverting is not a formality and row 4 is the proof.** `bug-fixed-array-assignment-no-copy`
was fixed generally in v72 and a full revert of `aesgcm.pas` still segfaulted at
the GCM path, with no minimal reproducer. So each revert is a measurement, and a
failed one is a finding worth a new ticket rather than a reason to leave the row
where it was.

## Why this shape is worth more than the four reverts

A section header is a claim, and this one is load-bearing in the direction that
does not get audited: **"waiting on an open bug" tells a reader the code is
non-idiomatic for a reason that still exists, which is precisely the sentence
that stops them looking.** The entry is not wrong about the workaround, and not
wrong about the bug — only about the bug's *state*, which is the one part that
changes without anyone touching the ledger.

The same shape has turned up four times in this audit in one night, always
hiding **completed** work: a ticket cited by its `backlog/` path after it moved
to `done/`; a doc citing paths that live on `origin/wasm`; an Open question
answered seven weeks earlier; and now a revert queue whose items are all
unblocked. Each reads as conservative — *not done yet*, *not found*, *still
open* — and pessimism is the direction nobody double-checks.

## A second, smaller ask: the heading is creating the reading problem

Separable from the four reverts and probably cheaper. **Rows 3, 4 and 7 are not
waiting on an open bug either** — they are deliberate keeps with a written
reason, and two of them will still be keeps after every bug in this file is
closed. They belong under a heading that says so.

The reason to bother: **a section that is 7/8 wrong stops being read as a
queue.** The four live reverts did not sit there because anyone decided against
them; they sat there because the section they are in stopped rewarding a read.
Splitting the deliberate keeps out leaves a short list where every row is a
claim someone can check in a minute, which is the only version of this file that
survives its own lifecycle rule.

## Not in scope

The **Cleanup backlog** section (line 93) and the several **Reverted** sections
below it. Those are correctly filed and the Reverted ones are records.
