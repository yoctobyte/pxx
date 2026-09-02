---
track: T
prio: 25
type: bug
status: rejected
owner: unassigned
blocked-by: []
found: 2026-08-30
found-by: pxx-a5, while auditing the harness for swallowed exit statuses
summary: "test-core's language-skeleton loop runs the plain compile with a bare ';' while the very next compile has '|| exit 1'. A failing plain compile does not stop the loop -- it falls through to comparing an empty 'plain' against 'ts' and still fails, but reports '--threadsafe changes the output' for a defect that has nothing to do with --threadsafe. Not a status hole; a diagnosis-quality one."
---

# A failing plain compile is reported as a `--threadsafe` difference

- **Type:** bug (diagnosis quality) — **Track T** (the harness recipe).
- **Found:** 2026-08-30 by pxx-a5, in the same scan that cleared testmgr of the
  swallowed-exit-status class. **Filed against its own judgement** that this was a
  discipline note rather than a ticket — see below.

## The defect

test-core's language-skeleton loop:

```
./compiler/pascal26 $src $plainbin >/dev/null;      # bare ';'
<next compile>                     || exit 1        # guarded
```

A failing **plain** compile does not stop the loop. It falls through to comparing an
empty `plain` against `ts`, so the job **does** go red — the failure is not lost. But
the message says **`--threadsafe changes the output`** for a defect that has nothing to
do with `--threadsafe`.

## Why it is worth fixing

The red is honest and the *diagnosis* is not, which is the more expensive half: whoever
picks this up starts on the threadsafe path, and the failing plain compile is not
mentioned anywhere in the report. Same family as the `2> file` capture that reddened a
correct compiler because pxx prints diagnostics on stdout, and as face 174 where the
probe's formatter could not represent the answer — **a layer between the defect and the
reader's understanding of it, quietly answering a different question.**

This one is the *wrong-message* member of that family rather than the wrong-value one.

## Fix

`|| exit 1` on the plain compile, matching the line below it. Confirm the loop's other
bare-`;` lines are deliberate before closing — a double case, so **grep for the sibling.**

## Why this is a ticket and not a note

pxx-a5 judged it *"worth a discipline note rather than a ticket"*, and that is a
reasonable call on its size. Filed anyway, deliberately: **a discipline note has no
owner and no trigger.** Tonight produced six independent instances of load-bearing state
recorded where no tool reads it, which is the whole reason the family index exists. The
cost of a low-prio ticket that turns out to be trivial is one read; the cost of a note
nobody re-encounters is that it is rediscovered by whoever next chases a phantom
`--threadsafe` bug.

## Rejected 2026-09-02 — the Track T tooling backlog was cut as a pile

Owner decision, not a judgement on this ticket individually. 73 of the 74 open
`track: T` tickets were filed between 2026-08-31 and 2026-09-02, 58 on one day.
The pile was too large to work through, and a ticket nobody will fix does not sit
neutrally: it stays in the ranker forever at zero value, which is the same
argument CLAUDE.md already makes for `rejected/` over a low prio.

Four were kept, on a purely structural test — an active umbrella, or a hard
`blocked-by:` edge from live non-T work: `umbrella-one-full-tier-run-with-no-red-tier`,
`feature-t-freebsd-image-and-runner`, and the two `regression-test-core-*` reds
that block the umbrella.

**This is a reversible archive, not a deletion.** If one of these is refiled
later, it should be refiled with the evidence that makes it worth doing rather
than restored wholesale.
