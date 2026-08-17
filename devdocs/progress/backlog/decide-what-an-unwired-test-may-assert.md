---
slug: decide-what-an-unwired-test-may-assert
track: U
prio: 55
status: backlog
---

# May we record our own output as the expectation?

**Read time: 3 minutes.** One principle question, three options, a recommendation.

## The measurement

`tools/check_test_wiring.py` found 98 test files no build rule runs. Ten had an
`.expected` sibling and shipped alongside a fix in the last two days; those are
wired now (`66de48a84`, `38a88a8b8`, `56edf4392`) and all pass.

Track T then triaged the remaining 85 in ~11 seconds (85 compile-only invocations
at ~0.13s each):

| bucket | count |
| --- | ---: |
| compiles today | 61 |
| helper module, correctly not a rule | 5 |
| blocked bare, but builds with the right flags | ~5 (synapse smokes need `--mimic-fpc -Fuexternal/synapse`; some want `-I`) |
| genuinely blocked | ~10 |

The ~10 carry a compiler error as their exemption reason — an observation, not a
summary — so `UNWIRED.txt` is the right home for exactly those.

## The fork

**None of the 61 has an `.expected` file.** The ten that did were the ten already
wired. So "trivially wireable" overstates it: they compile, but wiring one means
**deciding what it should assert**, and there is no recorded answer to inherit.

That is a principle question, not a chore:

1. **Record current output as `.expected`.** Fast — 61 files, mechanical, done in
   an afternoon. And it **cements whatever the compiler does today as correct**,
   including any bug. A test built this way cannot fail for the reason tests
   exist; it can only detect *change*, and it will defend a wrong value as
   loyally as a right one.
2. **Verify each against the reference implementation first**, then record: FPC
   for Pascal, gcc for C, CPython for NilPy. Honest, and the oracles and probes
   already exist (`tools/fpc_diff_probe.sh`, `gcc_diff_probe.sh`, `pydiff.py`).
   Slower, and it will surface bugs — 61 files against an oracle is a bug hunt
   wearing a wiring task's clothes.
3. **Assert only "compiles and runs without failing"** — no output comparison.
   Immediate, honest, records nothing false. Weak: it catches crashes and
   regressions-to-crash, nothing about values.

## Recommendation

**3 as the floor, 2 where an oracle exists, never 1.**

Option 1 is the one to rule out explicitly, because it is the tempting one and it
inverts what a test is for. This repo's whole method is differential — every
recorded wrong root cause here was a plausible story nobody diffed against an
oracle — and recording our own output as truth is that failure made permanent and
given a green tick. Worse, it is invisible afterwards: nothing in the file says
"this expectation was never checked against anything."

Then: C files largely self-assert (`assert()` / non-zero exit), so option 3 costs
almost nothing there and is genuinely sufficient. Pascal and NilPy files need an
expectation, so those get option 2 — and the bugs it finds are the point, not a
cost overrun.

If option 2's yield is too slow to absorb, the honest fallback is to wire fewer
files properly rather than all 61 cheaply.

## What changes on each answer

- **3+2:** ~61 files wired over some days, a stream of new bug tickets, no false
  expectations recorded.
- **1:** all 61 wired this week, and an unknown number of bugs permanently
  blessed with a passing test in front of them.
