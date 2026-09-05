---
track: T
prio: 35
type: feature
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "gate.sh's `pinned builds live lib/rtl` row printed PASS in 1s while sampling one fixture of 111 units, and the seam had moved off that fixture (b6212f43f). Four gates ran that afternoon and none measured the row; cost was the only tell and nobody read it. A guard's RUNTIME is a checkable proxy for its POPULATION — implausibly cheap for the work it claims means it is sampling — and unlike a positive control it needs no knowledge of the defect. Proposes recording per-arm wall time and flagging an arm whose cost falls far below its claimed denominator. NOT a timing benchmark and must not become one: the question is orders of magnitude, not milliseconds."
---

# A guard whose runtime is implausibly small for its population is sampling

## The incident

`gate.sh quick`'s `pinned builds live lib/rtl` arm compiled **one** fixture,
`test/test_uses_sysutils.pas`, and reported **PASS in 1s** while 20 of 111
`lib/rtl` units and the whole of `lib/pcl` could not be compiled by the pin at
all. `b6212f43f` fixed the sampling; the same row now takes ~49s and finds 12 of
54 root units failing.

Four `gate.sh quick` runs finished that afternoon before the fix landed. **None
of them measured that row**, and every one of them reported it green.

## Why this is worth a mechanism and not just a lesson

**Cost was the tell, and it was visible the whole time.** A row claiming to
answer "does the pinned compiler still build lib/rtl" cannot do it in 1s; 111
compiles cannot fit. That inference needs **no knowledge of the defect**, which
is what makes it different from a positive control — a control has to be drawn
from the population your question is about, and you have to know what the
question is. Runtime plausibility is checkable by someone who knows neither.

It is the same family as `tools/instrument_denominator` reasoning already in the
handbook: **an instrument that reports a RESULT should report its DENOMINATOR.**
Runtime is a denominator nobody has to be told to emit — it is already measured,
already printed, and already ignored.

## Sketch, deliberately crude

- `gate.sh` already prints `(49s)` per arm into `summary.log`. Record the arm's
  claimed population where it has one (root units swept, files scanned, cases
  run) beside its wall time.
- Flag an arm whose seconds-per-unit falls **orders of magnitude** below its own
  history, not below a threshold someone picked.
- A drop is not automatically a failure — a genuine speedup looks the same. It
  is a **question**, and the arm should have to say which.

## What this must NOT become

A timing benchmark. The box is contended, loads of 12-17 are ordinary here, and
wall time is noisy by a factor of several. **The signal is orders of magnitude —
1s versus 49s — and anything that starts caring about 20% has become a different
and much worse tool.** If it cannot be kept crude it should not be built.

## Provenance

Observed by frank-coordinator from frankB's four gates and the landing time of
`b6212f43f`, and filed here at its request rather than left as a remark in a
message. Related: `bug-t-thirteen-devtest-guards-assert-a-code-line-s-spelling-
as-a-proxy-for-a-behaviour` — a different way a guard stops covering while still
printing PASS.
