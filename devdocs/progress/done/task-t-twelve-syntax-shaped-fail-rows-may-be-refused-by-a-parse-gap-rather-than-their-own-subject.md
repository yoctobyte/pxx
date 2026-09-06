---
track: T
prio: 45
type: task
blocked-by: []
status: done
found: 2026-09-06
found-by: frank-coordinator
owner: frankS
summary: "Residual named by frankS in `109fbebb1` and not addressed there: of the 191 refused `%FAIL` rows in the curated Pascal conformance categories, **12 are refused with a syntax-shaped diagnostic** (`expected ':' before 'X'` and kin). A `%FAIL` row asserts only THAT the compile is rejected, never WHICH refusal -- so a row refused by an unrelated PARSE GAP is green for a reason that has nothing to do with its subject, exactly as the 4 unit-source rows were before they were auto-gated. Each of the 12 needs reading once: either the parse gap IS the row's subject (green for the right reason, record it) or it is not (the row is vacuous and the real assertion is unmeasured, and it goes red the day the gap closes). This is an INSTRUMENT audit, not a feature-gap list -- the deliverable is a disposition per row, and any genuine parser hole it turns up is a separate Track P ticket. Unowned and explicitly not claimed."
---

# Twelve syntax-shaped `%FAIL` refusals: green for their own reason, or green by accident?

- **Type:** task (instrument audit)
- **Track:** T (the runner and its dispositions). Any parser hole found is **Track P**.
- **Status:** done
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

## 2026-09-06 (frankS) — all twelve dispositioned. SIX are vacuous.

Method: for each row, compile it, take the refusal, then **probe the same
construct in a context where it is LEGAL**. That probe is the discriminator — a
row refused at its own construct is only a real pass if pxx accepts that
construct where the language allows it. Without it, "refused at the right token"
and "does not support the token at all" are indistinguishable.

### VACUOUS — refused by something that is not the row's subject (6)

| row | its subject | what actually refused it |
| --- | --- | --- |
| `tgeneric100` | unit-qualified `specialize ugeneric99.TTest<LongInt>` | an error **inside `ugeneric99.pp`**, a used unit — the row's own source is never reached |
| `tgeneric101` | same | identical, same other file |
| `tclass14a` | `stored` is not supported on a CLASS property | **`stored` is not supported at all** — probe: an ordinary `published property ... stored False`, which FPC accepts, is refused too |
| `tclass10b` | a visibility section after `type` resets the section, so a field decl there is illegal | the **ORDER** `type private`. Probe: `private type` is ACCEPTED, `type private` is not; FPC takes both, so the row dies before its own construct |
| `tclass17` | `threadvar` is not allowed in a class | **`threadvar` is not supported at any scope** — probe: a program-level `threadvar` is refused |
| `terecs21` | same as `tclass17` | identical |

### LEGITIMATE — refused at the row's own construct (6)

| row | why the probe clears it |
| --- | --- |
| `toperator7` | the source is literally `AValue = 1;` under `// this construction must fail`, and pxx answers `expected ':=' before '='`. The row's exact rule. |
| `terecs4` | `destructor` in a RECORD. Probe: a destructor in a CLASS is accepted, so the refusal is about the record context. |
| `tsealed5` | `sealed` on an OBJECT. Probe: `sealed` on a CLASS is accepted. (Mechanism differs — pxx reads `sealed` as a field name — but the construct refused is the row's.) |
| `tprop2` | `property` at program level. Probe: `property` in a class is accepted. |
| `tgeneric31` | already documented in `IsGenericRoutineHeaderAhead`'s own comment: the `<`-alone spelling used to ACCEPT this row, and was fixed precisely because it is `%FAIL`. |
| `tgenfunc11` | `virtual` on a generic method. Refused, and only reachable on code FPC also rejects, so it is a programmer error either way (CLAUDE.md: ask what the source MEANT). Fragile in mechanism — the zero-uses erase leaves the modifier — but `overload;` on the same shape is measured to work and run, so no legal program depends on it. |

### Not re-refused, per this ticket's own instruction

None of the six vacuous rows is being made to fail "properly" to keep it green.
They are recorded as what they are. Three of them are a `%FAIL` row that pxx
would pass on the rule if the parse gap closed, and two (`tgeneric100/101`)
would need the OTHER file to parse first.

### THREE COMPAT GAPS FELL OUT, and they are the actual value here

Each is a separate Track P ticket per this ticket's boundary, each measured by a
probe on code **FPC accepts**:

- **`stored` on a property is unsupported** — `published property F: Integer read FF write FF stored False;` is refused. This one has a real consumer: `stored` is a streaming/RTTI attribute and `lib/pcl` is a widget set.
- **`threadvar` is unsupported at any scope** — `threadvar t: LongInt;` at program level is refused.
- **`type <visibility>` order in a class body** — `private type` accepted, `type private` refused; FPC takes both.

Filed separately. Ranked on how much real code wants them, not on how the corpus
row is spelled.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 62749a0a6.
