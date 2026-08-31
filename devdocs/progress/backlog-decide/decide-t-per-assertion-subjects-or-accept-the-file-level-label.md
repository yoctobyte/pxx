---
slug: decide-t-per-assertion-subjects-or-accept-the-file-level-label
title: "Build per-assertion subject labelling, or accept the file-level label as future-only?"
track: U
prio: 25
type: decide
blocked-by: []
status: backlog
owner: ""
created: 2026-08-28
summary: "The float-red labelling mechanism is live but has zero adopters, and structurally cannot gain any: it labels a whole JOB, while every file that motivated it mixes last-digit accuracy with a NaN fault, a missing name, an 84-ulp regression or a formatting bug. The only remaining shape is per-assertion subjects -- real machinery in T's tooling plus a pass through N's files, entirely in service of the subject the owner has called low prio by definition four times, and whose motivating reds have not appeared in 259 runs. Recommendation: accept the file-level label as future-only, build nothing more."
---

# The fork

`bug-t-a-one-ulp-move-turns-the-fleet-red-and-outranks-its-own-prio` established
a real mechanism: a red job is triaged at the priority of *being red*, not at the
priority of its subject, so a one-ulp float regression re-enters the queue at the
top through a door the `prio:` field cannot reach. 23 such events are on record.

The fix shipped on 2026-08-26 was labelling: a red still fires at full strength
but arrives carrying the subject its own source declares, so the triager sees
"low prio by the owner's standing rule" in the line they are already reading.

**Measured 2026-08-28, that mechanism has never fired.** Zero tests declare a
subject; zero float-named red events in the 259 runs since it landed.

And it cannot gain adopters as built. `job_subject()` returns **one subject per
job**, i.e. per file — the same granularity the ticket used to reject its own
shape 2 — while every motivating file mixes subjects:

| file | what a `float-accuracy` label would de-prioritise |
| --- | --- |
| `math_domain_errors` | a NaN / -Inf handling fault — the escape rule excludes it outright |
| `math_log` | a missing name (`undefined variable (log)`) — explicitly NOT F |
| `pow_matches_cpython` | an **84 ulp** regression, not one |
| `float_pow_oracle` | the same span, differentially |
| `str_float` | `str(3.14)` — a formatting bug, not last-digit noise |

So the honest state is: the label is correct, costs nothing, and has no
applicable subject in today's corpus.

# The options

**A — accept the file-level label as future-only; build nothing more.**
*(recommended)* Item 1 of the parent ticket closes as "not adoptable" rather
than "done". The marker stays for a future test whose subject genuinely is
last-digit accuracy end to end. Cost: nothing. Risk: the original door stays
open, so a float red still commands attention at red-priority when one occurs.
The measured mitigation is that none has occurred in 259 runs.

**B — build per-assertion subjects.** The granularity the parent ticket
identified as correct. A subject would attach to an individual expectation
rather than a file, so `pow_matches_cpython` could de-rank its 1-ulp assertions
while its 84-ulp guard stays full strength. Cost: real machinery in T's tooling
(the expectation format, the comparison path, the report line) **plus** a
per-assertion pass through Track N's `.npy` files by a lane that knows which
assertion pins a rendering and which pins a contract. Risk: it is significant
infrastructure whose entire subject is float accuracy.

**C — shape 1, tolerance comparison**, per assertion, in N's files. Same
granularity as B and the parent ticket's stated preference, but it changes what
the tests *assert* rather than what a red *says*. Strictly more invasive; the
parent ticket notes it is "the most work".

# Why this is Track U and not a lane call

Three facts point one way and I would rather have them confirmed than assumed:

- the owner has ruled float accuracy low prio **by definition**, four separate
  times, and once broadened it to formatting as well;
- B and C are substantial work whose *whole subject* is managing the priority of
  that lowest-prio subject — the shape of thing that quietly becomes the drain
  the `float/` folder exists to stop;
- the motivating reds have not been observed in 259 runs, so the urgency that
  justified the ticket is not currently present.

Against that: the mechanism is real and was worth recording, and "it has not
fired lately" is not proof it will not. The parent ticket is deliberately still
open for that reason, and A leaves it open rather than closing it.

# Recommendation

**A.** Accept the file-level label as future-only, close the adoption item as
not-adoptable, and revisit only if float reds resume at the historical rate —
which the archive can answer cheaply at any time. If the answer is B or C, it
should be scheduled as ordinary Track N work at float's own priority, not as a
tooling emergency.
