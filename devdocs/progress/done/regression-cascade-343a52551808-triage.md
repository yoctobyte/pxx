---
track: T
prio: 40
type: regression
status: done
---

# triage: the 17-job CASCADE at bad=343a52551808 — its 5 NilPy jobs are GREEN natively at HEAD

tstate has carried an open **CASCADE, 17 jobs**, `bad 343a52551808`, last good
`c8f5070671be`, 67 commits in range. No ticket existed for it, so it was
appearing in every `twatch --status` and being scheduled by nobody. Filed here as
a triage record; **Track T owns the call**, this is a hand-off, not a claim.

## Measured 2026-08-16 at HEAD (096da361d), native x86-64

The 5 NilPy jobs, built with a self-hosted fixedpoint compiler at HEAD and
diffed against their `.expected`:

| job | result |
| --- | --- |
| `test_nilpy_encode.npy` | runs clean (no `.expected` in the tree) |
| `test_nilpy_encode_decode_codecs.npy` | **GREEN** |
| `test_nilpy_intrinsic_result_chain.npy` | **GREEN** |
| `test_nilpy_math_domain_errors.npy` | **GREEN** |
| `test_nilpy_math_log.npy` | **GREEN** |

One trap worth recording, because it cost a false "DIFFERS" here first:
`test_nilpy_intrinsic_result_chain` opens `test/nilpy_chain_input.txt` by a
**repo-root-relative** path, so running the binary from a scratch directory
fails with `FileNotFoundError` and looks exactly like a regression. Run it from
the repo root.

The other 12 jobs are the **uforth corpus**, deliberately NOT run here: it is a
~150s suite, and it has its own precondition — `__file__` is the BINARY, so
`STD.UFO` must sit beside it, and the suite blocks on an interactive `ACCEPT`.
A cascade whose members are 12 corpus jobs plus 5 unrelated NilPy tests that are
green is the shape of a **precondition or environment failure on plexus**, not
of one compiler regression; note tstate separately reports 2 jobs SKIPPED on
plexus for exactly "absent corpus or unmet precondition".

## What would settle it

Re-run the cascade on plexus against current HEAD. If the NilPy five come back
green there too, the cascade is uforth-only and the question is whether
`STD.UFO` is present in the watcher's clone — an environment fix, not a bisect.
Bisecting 67 commits for a cascade whose non-corpus members already pass is the
expensive way to learn the same thing.

## Settled 2026-08-17 by Track T — the cascade is CLOSED, and it closed legitimately

The ticket named the test: *"re-run the cascade on plexus against current HEAD."*
It no longer needs running — the cascade is gone from tstate, and the question
that remains is whether it went for a good reason or was silently dropped.
Checked, because "the entry vanished" and "the jobs are green" are different
facts and only one of them is reassuring:

```
open_regressions on plexus:  1   (lib-test#src:test/crtl_exp2.c — unrelated)
"343a52551808" in tstate/*.json, TSTATE.md:  absent
```

All 17 members, from plexus' own recorded job map:

| members | recorded status |
| --- | --- |
| the 5 NilPy jobs | **pass**, all five |
| the uforth jobs (14 now, was 12) | **pass**, all fourteen |

So the closure is the ledger working, not an entry being lost: `reg_open()`
drops an entry once its jobs pass in the authoritative map, and every member
passes. Nothing here is a compiler regression, which is what the native
measurement in this ticket already predicted.

**The diagnosis in this ticket was right and is worth keeping** even though the
cascade closed on its own. A cascade whose members are a corpus suite plus five
unrelated tests that are green natively is the shape of a precondition or
environment failure, not one compiler defect — and that reading held: the
uforth jobs came back once their precondition was met, and no compiler fix was
ever attributed to them.

Two things carried forward rather than discarded with the ticket:

1. **The `test_nilpy_intrinsic_result_chain` trap.** It opens
   `test/nilpy_chain_input.txt` by a **repo-root-relative** path, so running the
   binary from a scratch directory fails with `FileNotFoundError` and looks
   exactly like a regression. That cost a false "DIFFERS" once already; it will
   cost it again. Now recorded where a triager will hit it.
2. **The uforth job count moved 12 → 14** while this sat open, with nobody
   splitting anything — the same keyspace drift noted in
   [[chore-t-split-lib-test-into-jobs-that-name-what-failed]]. A cascade's member
   list is a snapshot, so an old cascade entry cannot be compared member-for-member
   against a current job map; compare by *name*, as done above, never by count.

No bisect was owed and none was spent. Resolving.

## Log
- 2026-08-17 — resolved, commit 5a0197a21.
