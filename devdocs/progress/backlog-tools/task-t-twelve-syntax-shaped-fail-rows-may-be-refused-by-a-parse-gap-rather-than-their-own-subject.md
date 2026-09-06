---
track: T
prio: 45
type: task
blocked-by: []
status: backlog
found: 2026-09-06
found-by: frank-coordinator
owner: ""
summary: "Residual named by frankS in `109fbebb1` and not addressed there: of the 191 refused `%FAIL` rows in the curated Pascal conformance categories, **12 are refused with a syntax-shaped diagnostic** (`expected ':' before 'X'` and kin). A `%FAIL` row asserts only THAT the compile is rejected, never WHICH refusal -- so a row refused by an unrelated PARSE GAP is green for a reason that has nothing to do with its subject, exactly as the 4 unit-source rows were before they were auto-gated. Each of the 12 needs reading once: either the parse gap IS the row's subject (green for the right reason, record it) or it is not (the row is vacuous and the real assertion is unmeasured, and it goes red the day the gap closes). This is an INSTRUMENT audit, not a feature-gap list -- the deliverable is a disposition per row, and any genuine parser hole it turns up is a separate Track P ticket. Unowned and explicitly not claimed."
---

# Twelve syntax-shaped `%FAIL` refusals: green for their own reason, or green by accident?

- **Type:** task (instrument audit)
- **Track:** T (the runner and its dispositions). Any parser hole found is **Track P**.
- **Status:** backlog, unowned, filed 2026-09-06.

## Where the number comes from

`109fbebb1` (frankS) re-ran every curated `%FAIL` row and recorded **why** each is refused.
**225 rows, 191 refused**, grouping as:

| group | rows | disposition |
| --- | --- | --- |
| impossible operator overload | 41 | refused for the row's own reason |
| **syntax-shaped** | **12** | **this ticket — unknown** |
| undefined variable | 11 | refused for the row's own reason |
| "this file is a unit, not a program" | 4 | **vacuous** — auto-gated in `109fbebb1` |

The unit group is the proof that the question is worth asking: pxx has no standalone-unit
compile, so it refused those rows for a property of the FILE KIND, and **every one passed
whatever it contained.** `tgeneric105` was counted as a pass on exactly that, and
`tgenfunc14/17/18` carried skip reasons describing a dialect-pass the compiler never reached
the source to have. 4 curated rows, **9 in the corpus.**

## What "done" looks like

A disposition per row, in the row's own skip/notes line, saying **which** refusal it got and
whether that refusal is the assertion. Two outcomes and both are wins:

- **The gap IS the subject** — record it, and the row is honestly green.
- **The gap is NOT the subject** — the row is vacuous. It must not be re-refused to keep it
  green (see the playbook: *a red is the signal that a FEATURE LANDED*). It needs either a
  gate, like the unit case got, or a re-measure trigger naming the gap whose closure will
  turn it red.

**Do not close this by counting.** The question is per row and the instrument is reading the
diagnostic, not grepping for one.

## Why it is not the long tail ticket

[[task-pascal-conformance-long-tail]] is a catch-all list of **known parser holes**. This is
the opposite direction: rows currently **passing**, where the pass may be an artefact. A hole
found here feeds that ticket; the audit itself does not live there.

## Related

- Playbook, `## "IT PASSED AT THE PIN" AND "IT PASSED FOR THE REASON IT NAMES" ARE DIFFERENT
  CLAIMS` and its 2026-09-06 postscript.
- Playbook, `## A RULE SPELLED PER CALLER FAILS BY AN ABSENT COPY, NOT A DIVERGENT ONE`.
- [[bug-t-the-conformance-runner-reports-an-empty-corpus-as-a-normal-green]] — the same
  family: a green that measured nothing.
