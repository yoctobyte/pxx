---
track: T
prio: 40
type: bug
status: backlog
owner: unassigned
blocked-by: []
found: 2026-09-04
found-by: frank-optimize, while landing feature-opt-inline-float-and-record-returning-leaves
summary: "pasmith.py generates no float code at all — zero Double/Single declarations across five seeds at optfuzz.sh's own flags, and there is no --floats knob. So tools/optfuzz.sh, which exists specifically because curated gates missed 21 silent -O3 inliner divergences, is structurally blind to every float optimization. A clean optfuzz run on a float-only change is a guard that cannot fail, and it prints the same PASS as a real one."
---

# pasmith emits no floats, so optfuzz cannot see any float optimization

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
