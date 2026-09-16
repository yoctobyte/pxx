---
slug: bug-t-optdiff-counts-an-argument-taking-program-as-a-pass-while-sweeping-only-its-usage-path
title: "optdiff counts an argument-taking program as a pass while sweeping only its usage path"
track: T
prio: 20
type: bug
status: new
created: 2026-09-16
found: 2026-09-16
found-by: frankb-56, closing the two glob optdiff reds
owner: ""
blocked-by: []
summary: "MEASURED AND SMALL -- filed at p45 with the population unknown, now p20 because I counted it. A 105-program random sample of the 2885-file corpus (fixed seed, reproducible) found ZERO argument-requiring programs beyond the two already known, so the glob pair is plausibly most of this class. Rule of three puts the 95% upper bound at 3.3%, i.e. at most ~96 of 2885 -- a loose bound, and I am not claiming tighter than the sample supports. Kept rather than closed because the mechanism is real and reproducible: a program that exits before doing its work agrees at all four O levels and lands in `pass=`. THE CENSUS FOUND A DIFFERENT DEFECT INSTEAD, and it is fixed: `[ $r0 -ge 124 ]` classified 125/126/127 as TIMEOUT-O0, so two object-import tests dying with `symbol lookup error: undefined symbol` were reported as too slow -- 124/137 are the timeout codes, 125-127 are exec failures meaning the program never started. They now report under their own EXEC-FAIL-O0 line with the rc. That was found ONLY because the census recorded outcomes instead of filtering on a usage-shaped guess; a prefiltered count would have returned 0 and missed it. Also recorded: rc=42 is a SUCCESS sentinel in 16 of the 90 programs that ran, which is the concrete reason rc alone cannot classify this population."
---

# optdiff sweeps the usage path and calls it a pass

`tools/optdiff.sh` invokes every program with no arguments and compares
stdout+stderr across `-O0/-O1/-O2/-O3`. A program whose `main` starts

    if (argc < 2) { fprintf(stderr, "usage: %s ...", argv[0]); return 2; }

agrees with itself at all four levels and lands in `pass=`. Nothing it exists to
test was executed.

## Why this is worth a ticket and not a shrug

The harness already treats invisible non-coverage as the enemy: `SKIPLIST`,
`BUILD-FAIL` and `TIMEOUT-O0` are each printed BY NAME, and the header says why
— *"a count alone cannot distinguish 'deliberately excluded' from 'this sweep
does not know how to build it'"*. This class defeats that, because it does not
reach any skip arm. It is counted as coverage.

It was found only because these two programs were **also** printing `argv[0]`,
which turned the silent gap into two loud false DIFFs and two p70 tickets.
`311649be0` removed the noise and left the silence.

## What is known

| | |
| --- | --- |
| known members | `test/c_crtl_glob.c`, `test/c_crtl_glob_no_leak.c` |
| both actually clean? | yes — swept by hand with an argument, four levels, byte-identical |
| population size | **unmeasured** |

## The measurement that would size it

A full-corpus run recording, per program, the no-args exit code — the
argument-requiring ones cluster at a nonzero rc with a usage-shaped line on
stderr. That is Track T's tier and is refused by the per-fix gate, which is the
whole reason this is filed rather than answered.

Note `*_fail.pas` programs legitimately exit nonzero, so rc alone does not
separate the classes and the census must not assume it does.

## Do NOT fix it with a per-test argument table

`tools/optdiff.sh`'s own header rejects exactly that for the `-I` flags: *"a
sidecar flags table is a second place the truth lives and would drift from the
Makefile."* The same objection applies here and is stronger, since the Makefile
already encodes each program's real invocation.

## Census result (2026-09-16, frankb-56) — the number came back SMALL

Random sample, fixed seed, 105 of 2885 corpus files completed before the run was
killed for host memory pressure (not this run's — 54G was free afterwards). **A
prefix of a SHUFFLED list is still an unbiased sample**, which is the only reason
the partial run is usable; the earlier alphabetical attempt would not have been.

| outcome | n |
| --- | --- |
| built and ran | 90 |
| build-fail at -O0 (optdiff skips these already) | 15 |
| **argument-requiring, usage path — the hypothesis** | **0** |
| exit 42 (a SUCCESS sentinel, not a failure) | 16 |
| exit 125–127, never started | 2 |

**The hypothesis scored zero.** Reported because a small number is the result
nobody has an incentive to publish, and it is genuinely useful: it means the two
known members are plausibly close to the whole class, and nobody needs to build
the per-test argument mechanism this ticket warned against.

**Bound, stated honestly:** 0/90 gives a 95% one-sided upper bound of 3.3% by the
rule of three — up to ~96 files. That is loose. Tightening it needs a larger
sample, and this ticket is no longer worth that.

## What the census found instead — fixed, not filed

`[ "$r0" -ge 124 ]` swept exec failures in with timeouts. `timeout` reports 124
(and 137 on SIGKILL); 125/126/127 are the shell's exec-failure codes and mean the
program never started. `c_obj_import_host.c` and `c_obj_fnptr_b.c` both exit 127
with `symbol lookup error: undefined symbol: pxx_sum` / `call_handler` and were
both reported as `TIMEOUT-O0` — a reader chases performance for a binary that
never ran. They now appear under `EXEC-FAIL-O0` with their rc.

**This is the whole argument for recording outcomes rather than filtering on the
hypothesis.** A census that had grepped for usage-shaped output would have
returned 0, confirmed nothing, and never seen the mislabelled pair.
