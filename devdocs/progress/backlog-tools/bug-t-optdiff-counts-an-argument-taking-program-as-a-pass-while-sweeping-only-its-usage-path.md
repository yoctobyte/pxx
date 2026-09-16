---
slug: bug-t-optdiff-counts-an-argument-taking-program-as-a-pass-while-sweeping-only-its-usage-path
title: "optdiff counts an argument-taking program as a pass while sweeping only its usage path"
track: T
prio: 45
type: bug
status: new
created: 2026-09-16
found: 2026-09-16
found-by: frankb-56, closing the two glob optdiff reds
owner: ""
blocked-by: []
summary: "optdiff runs every corpus program with NO arguments. A program that requires one exits on its usage line, so the four O levels agree trivially and it is counted in `pass=` while nothing about it has been swept -- a guard that cannot fail, sitting INSIDE the pass count rather than in the SKIPLIST/BUILD-FAIL lines the harness added specifically so a count could not hide a decision. Found because two such programs (c_crtl_glob, c_crtl_glob_no_leak) were instead reporting a FALSE DIFF for nine days on argv[0]; fixing that in 311649be0 converted them from a loud wrong answer into a silent empty one, which is the worse failure and is why this is filed rather than left. Swept by hand with their argument, both are clean at all four levels (37 glob rows byte-identical; allocs=115763 frees=115741 live=22 at -O0/-O1/-O2/-O3), so there is no defect behind them -- the gap is coverage, not correctness. SIZE IS UNKNOWN AND NEEDS THE ONE INSTRUMENT THIS SEAT'S GATE EXCLUDES: a full-corpus run recording which programs exit nonzero under no-args, which is Track T's own tier. NOT PROPOSING THE OBVIOUS FIX: a per-test argument table is the sidecar the harness header already rejects by name, because it is a second place the truth lives and drifts from the Makefile."
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
