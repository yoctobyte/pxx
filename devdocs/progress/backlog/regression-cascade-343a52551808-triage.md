---
track: T
prio: 40
type: regression
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
