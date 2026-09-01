---
track: T
prio: 45
type: task
found: 2026-09-01
found-by: frankC
summary: "A test row whose corpus tree is absent echoes SKIP and passes, and nothing counts how many did. Measured on this box: test-core's crtl_tiny_regex_match row was UNGUARDED, so a missing library_candidates/tiny-regex-c hard-errored and — because make stops at the first failing recipe line — took 844 of test-core's 1745 compile rows (48%) with it, with no indication in the log of how much had not run. Guarding it (2026-09-01) fixes that and buys the opposite failure: testmgr's own TIERS comment records test-fgl printing SKIP and PASSING for its entire life without running once. Both failure modes are live in this repo TODAY. The missing mechanism is the same one test-c-abi-mixed-link now has: count the skips and report `N of M measured, K skipped`, so a box quietly running half the suite is visible in the verdict instead of indistinguishable from a green one."
---

# A corpus tree's absence should be counted, not just echoed

Three `library_candidates` dependencies live inside `test-core`, and until
2026-09-01 they handled absence three different ways:

| row | tree | on absence |
| --- | --- | --- |
| `test-fgl` | `library_candidates/fpc-rtl` | guarded, echoes SKIP |
| `stb_sprintf_probe` | `library_candidates/stb` | guarded, echoes SKIP |
| `crtl_tiny_regex_match` | `library_candidates/tiny-regex-c` | **hard error** |

The third was fixed to match the first two, because 844 dark rows is worse than
one announced absence. **That fix is not the end of the problem, it is the
other half of it.**

## Both failure modes have already happened here

- **Unguarded**: one missing checkout ends the run. 48% of `test-core` was not
  failing — it was never reached, and `make`'s own error line pointed at
  `Makefile:9272` while the command that actually failed was at 9537.
- **Guarded**: `tools/testmgr.py`'s `TIERS` comment records `test-fgl` guarded
  on `/usr/share/fpcsrc`, *absent from every box here*, printing
  `SKIP (no fpcsrc)` and passing **for its entire life without running once**.

So neither "make it loud" nor "make it skip" is the answer on its own. A skip
is only safe when somebody can see how many there were.

## The mechanism already exists in this tree

`test-c-abi-mixed-link` prints `N of M targets measured, K skipped` and goes RED
when `N` is zero — a skip is free, but a run that measured *nothing* can never
report PASS. `test-core` has ~1745 rows and no equivalent: it cannot say how
many it ran, so a box with three missing trees and a box with none produce the
same green.

**Suggested shape**, deliberately not prescriptive about the implementation:

- every guarded row increments a skip counter with its name;
- the target prints `test-core: R rows ran, S skipped` at the end;
- `testmgr` records `S` in the run's JSON beside the existing `skips`/
  `skip_holes` fields, which already exist for exactly this purpose at the JOB
  level and would then mean the same thing one level down.

## Why this is filed rather than done

The counting belongs in the harness, the rows belong to whoever owns each test,
and getting it wrong in the safe-looking direction produces a number that
always reads zero. Track T owns the tool. Filed by Track A/C after tripping
over the unguarded row while gating an unrelated C-frontend fix; the guard
landed in the same commit, the counting did not.

## The recovery, measured after the guard landed

Same box, same tree, the only change being the guard:

| | compile rows executed | `make` exit | MISMATCH |
| --- | ---: | ---: | ---: |
| unguarded | 901 | 2 | 0 |
| guarded | **1744** | **0** | **0** |

843 rows recovered, and **`0 MISMATCH` in both runs** — which is the whole
point. The unguarded run was not red because anything was wrong; it was red
because it stopped, and its zero mismatches covered barely half of what the
green run's zero covers. **Two identical-looking zeros, one of them worth twice
the other, and nothing in either log distinguishes them.**

That is the number this ticket wants surfaced. `test-core` currently cannot say
whether its green is a 1744-row green or a 901-row one.
