---
slug: bug-a-a-refcount-test-passes-at-o2-and-fails-at-o0-and-o1
track: A
prio: 60
type: bug
blocked-by: []
status: backlog
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "`test_threadsafe_refcount_lockfree` prints TSRCLOCKFREE FAILED at -O0 and -O1 and TSRCLOCKFREE OK at -O2 and -O3, with rc=0 every time — a silent wrong answer that changes with the optimisation level. Two rows: a string literal's handle is not born saturated, and its count is not bit-identical after SetLength churn. Both levels must be correct, so one of the two answers is a bug and it is not yet established which. Invisible until 2026-09-01 because the program did not build under optdiff at all and the -O2 arm was comparing -O2 against -O2."
---

# A refcount test passes at -O2 and fails at -O0/-O1

Measured 2026-09-01 by frankZ at `c9602d5ce`, binary `76c8be9064e0`.

```
DEFAULT  rc=0 : TSRCLOCKFREE OK
-O0      rc=0 : TSRCLOCKFREE FAILED
-O1      rc=0 : TSRCLOCKFREE FAILED
-O2      rc=0 : TSRCLOCKFREE OK
-O3      rc=0 : TSRCLOCKFREE OK
```

Deterministic: six runs of each binary produce a byte-identical output, and 60
runs of the -O1 binary exit 0 every time. The exit code is 0 in all five
cases, so nothing in the tier chain that reads only rc can see this.

The two failing rows:

```
FAIL literal handle is born saturated
FAIL literal count still bit-identical after SetLength churn
```

Both are about a STRING LITERAL's refcount handle. A literal's count is
supposed to be saturated — the sentinel that means "never free this, it is in
.rodata". At -O0/-O1 it is apparently not, or the test's way of reading it
(`PWord(Int64(Pointer(v)) - 16)^`) sees something different there.

**Which answer is right is not established and that is the work.** `-O2` being
the default does not make it the reference; `compiler.pas:908` calls `-O0` the
byte-identity reference. CLAUDE.md is explicit that both must be CORRECT, so
this is one bug either way: either the literal is mis-saturated below -O2, or
it is mis-read above it.

## Why nobody saw it

Two harness holes, both closed by `baae75b6b`:

1. The program **did not build** under optdiff. It reaches `__pxxclone`, which
   is refused without `--threadsafe`, and optdiff counts a build-fail as a
   skip. It had been leaving the sweep silently.
2. Even once it built, optdiff's baseline was compiled with **no -O flag**,
   which is -O2 — so the `-O2` arm compared -O2 against -O2 and could not
   report anything. With an explicit -O0 baseline the sweep now names it on the
   -O2 and -O3 arms.

So the first shard run that could see this program at all is the one that
found it. It blocks [[umbrella-one-full-tier-run-with-no-red-tier]] — optdiff
lives in the `opt` tier, and `pin_is_green` requires every judged tier green.
