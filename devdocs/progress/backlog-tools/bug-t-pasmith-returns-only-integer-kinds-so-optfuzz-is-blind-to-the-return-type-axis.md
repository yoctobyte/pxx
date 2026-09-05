---
track: T
prio: 40
type: bug
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-04
found-by: frank-optimize, while landing feature-opt-inline-float-and-record-returning-leaves
summary: "pasmith.py returns ONLY integer kinds from every function it generates -- measured across five seeds at optfuzz.sh's own flags, the complete set is longint/byte/word/longword/int64/smallint/shortint/qword. No float, no record, not even Boolean. It also declares no float variables at all, and while it DOES declare record types (3-4 per program) it never returns one. So tools/optfuzz.sh -- which exists specifically because curated gates missed 21 silent -O3 inliner divergences -- is structurally blind to ANY optimization keyed on return type, which is the whole admission axis of feature-opt-inline-float-and-record-returning-leaves. A clean optfuzz run on such a change is a guard that cannot fail, and it prints the same PASS as a real one."
---

# pasmith returns only integer kinds, so optfuzz is blind to the return-type axis

- **Type:** bug (tooling) — **Track T** (owns the tool).
- Found 2026-09-04 while admitting `tySingle`/`tyDouble` to the inliner.

## Measured

Five seeds, optfuzz.sh's exact generator flags
(`--funcs 6 --stmts 14 --depth 3 --vars 8 --recs 2 --arrs 2 --enums 1
--excepts 1 --classes 2 --objs 2 --strs 2`):

| | Double/Single declarations | float-returning functions |
| --- | --- | --- |
| seeds 11, 22, 33, 44, 55 | **0** | **0** |

`pasmith.py --help` has no float knob. The 28 case-insensitive hits for
`double|single|float` in the source are prose ("a single checksum line"), a
comment about a historical double-const bug, and one `argparse type=float`.

## Why it matters more than a missing generator feature

`tools/optfuzz.sh`'s own header says it exists because the curated gate battery
missed the depth-1 re-inline divergence — 21 silent -O3 miscompiles that only
random programs caught. It is the designated net for exactly the class of change
that touches splice machinery.

For a float-typed change that net **cannot fail**, and it reports the same clean
run as a real one. That is the shape CLAUDE.md names: a guard that cannot fail
is not a guard, and it prints PASS. It is worse than no coverage, because a
green optfuzz run reads as evidence.

## What would close it

A `--floats N` knob generating `Double`/`Single` locals, params and
float-returning functions, folded into the checksum like every other value.
The checksum is the constraint: floats must fold deterministically, so either
compare bit patterns or fold via a fixed-width integer reinterpretation rather
than by printing digits (a digit comparison measures the float FORMATTER, which
is a different subject — see `test/lib_math_correctly_rounded.pas`'s header).

**Positive control, per the rule this ticket is an instance of:** the new knob
ships with a seed that MUST produce a float-returning function, asserted — not
merely "a run that found nothing".

## Meanwhile

`feature-opt-inline-float-and-record-returning-leaves` is landing with optfuzz
run for the INTEGER path only, stated as such in its write-up rather than
claimed as float coverage.


## 2026-09-05 — the gap is WIDER than this ticket first said, and the correction matters

Filed as "no float code". Measured again while starting the RECORD half, and
the accurate statement is stronger: **pasmith never returns anything but an
integer kind.** Every `function` it emits across five seeds, complete set:

    longint 22 · byte 18 · word 16 · longword 14 · int64 14
    smallint 12 · shortint 12 · qword 12

No float, no record, no Boolean. It *does* declare record TYPES — 3 to 4 per
program — which is exactly the trap: a reader who greps for `record` in a
generated program concludes records are covered, and they are covered as
variables and fields while being entirely absent from the position that matters
here, the RETURN.

**Why the sharper version is worth the edit:** the original summary would let
someone conclude that the record half of
`feature-opt-inline-float-and-record-returning-leaves` was fuzz-covered because
its subject is records rather than floats. It is not. Neither half of that
ticket is reachable by optfuzz, for one shared reason — the generator's return
types — rather than two unrelated ones.

So the knob this ticket asks for is not "--floats". It is **return-type
coverage**: float returns, record returns, and Boolean returns, each with a seed
that MUST produce one, asserted.

**Renamed 2026-09-05** from `bug-t-pasmith-generates-no-float-code-so-optfuzz-cannot-see-float-optimizations`.
The old slug was 80% accurate, which is the worse kind: floats really are missing,
so a reader who sampled it was right about what was there and wrong about the
scope. Anyone searching for record- or Boolean-return fuzz coverage would not
have found this ticket under its old name. Body unchanged.
