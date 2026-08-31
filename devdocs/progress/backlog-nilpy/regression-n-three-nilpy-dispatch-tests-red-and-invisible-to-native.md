---
slug: regression-n-three-nilpy-dispatch-tests-red-and-invisible-to-native
track: N
type: regression
prio: 60
status: backlog
blocked-by: []
summary: "Three .npy dispatch tests that PASSED at the last full tier (43b462833, new_red: []) are RED at e7c0d1d2a. Test sources are byte-identical across the range, so the compiler is the only variable. Track O is EXONERATED by measurement. Two predate the -O window; the third narrows by exclusion to 79148ec99 fix(N) hasattr. They were invisible because test-nilpy is in limited/full, NOT native — by design."
---

# Three NilPy dispatch regressions, and why nothing caught them

- **Type:** regression — **Track N** (dispatch/lowering). Found by **Track T**
  during a requested full-tier sweep of `e7c0d1d2a`; filed here because *T owns
  the tool, never the bug*.
- **Found:** 2026-08-26.

## The reds

```
test-nilpy#src:test/test_nilpy_lowercase_name_vs_class.npy
test-nilpy#src:test/test_nilpy_isinstance_over_a_type_value.npy
test-nilpy#src:test/test_nilpy_builtin_over_variant_receiver.npy
```

Sweep: tier `full`, 3081 jobs, wall 2936s, `unreached: 0`, `timed_out: false`.
Compiler `80a9bef055…`, **`converged after 2 round(s)`** at `e7c0d1d2a` — the
provenance is stated because a sweep that cannot name its binary is not evidence
(see [[bug-a-the-selfhost-rule-is-a-no-op-when-the-seed-is-newer-than-its-sources]]).

## These are regressions, not new tests

All three **existed at the baseline full run `43b462833`** (2026-08-26T02:06Z),
which recorded `new_red: []` and only two `still_red` entries, neither of them
these. So they passed there and fail now.

And the experiment is clean: `git diff --name-only 43b462833 e7c0d1d2a` over all
six files (three `.npy`, three `.expected`) returns **nothing**. The test sources
and their expectations are byte-identical across the entire range. **The compiler
is the only variable.**

## Attribution — Track O is exonerated, by measurement

The 133-commit range contains five `perf(O)` passes, so the obvious question was
whether the optimiser did this. It did not.

A compiler built at **`d424445ce`** (= `e9317428d^`, immediately before the first
`perf(O)` commit), `converged after 1 round`:

| test | at pre-O | conclusion |
| --- | --- | --- |
| `lowercase_name_vs_class` | **FAIL** | already broken before Track O |
| `isinstance_over_a_type_value` | **FAIL** | already broken before Track O |
| `builtin_over_variant_receiver` | **PASS** | broke inside the 33-commit window |

For the third, only **six** of those 33 commits touch `compiler/`: five
`perf(O)` and `79148ec99 fix(N): hasattr on an untyped parameter answers the
receiver, not the program`. A compiler built at **`029f79b26`** — containing two
`perf(O)` commits and **not** the Track N fix — `converged after 2 round(s)` and
**PASSES**.

That leaves `79148ec99`, `f9d9da4b5`, `6692d08b8`, `e7c0d1d2a`. The last three
are gated behind `OptLevel >= 3`, and **these tests compile at the default
level** (`./$(COMPILER) test/x.npy out`, no `-O` flag), so they cannot reach it.

**Narrowed to `79148ec99` by exclusion — NOT bisected to it directly.** The
confirming build (at `79148ec99` and its parent) was not run before the session
ended, and that is the next step, not a conclusion. It is stated this way
deliberately: a `hasattr on an untyped parameter` fix and a `variant receiver`
dispatch test is a very good story, and every wrong root cause in this repo's
history was a plausible story nobody diffed.

The first two reds are older and need their own range; the baseline full at
`43b462833` bounds them from below.

## Why nothing caught them — the part that outlives the bugs

`test-nilpy` is in **limited/full, NOT native**, deliberately: enrolling ~300
NilPy jobs at native took the fast verdict from ~104s to ~235s, and native is the
tier dev boxes gate their pushes on (`tools/testmgr.py`, `TIERS`). The quick-tier
canary carries the broad-not-deep signal instead.

So the watcher's unbroken run of GREEN native verdicts **could not** have caught
these, by design — and breadth (limited/full) was 4h stale and 49 testable
commits behind when the sweep started.

**Three NilPy regressions sat invisible to the tier everyone gates on.** That is
the breadth-staleness cost arriving as concrete bugs rather than as a number, and
it now matters more than it did: `master` advances only on a pinned, fully-swept
sha, so Track T's throughput is master's throughput. The honest lever is fewer
commits between pins, not a thinner sweep.

## Not to be read as a full-tier verdict

~50 jobs **skipped** in that sweep — every `pascal-conformance` and
`c-conformance` shard, and every real-program corpus (`lua`, `cjson`, `zlib`,
`fgl`, `fpjson`, `sqlite-threads`). A skip is not a pass. The corpora were absent
from the scratch worktree; the daemon's own sweep in its proper clone is what
covers them. Separately, `testmgr` records an **empty `reason`** on every skip,
which is why this needed a paragraph instead of a line —
[[bug-t-a-skip-that-cannot-say-why-is-a-pass-in-the-verdict]].

One further red in that sweep, `test-smoke quick_canary_argv0.pas@2`, was an
**artifact** of running from a worktree under `/tmp` and is excluded: confirmed
by hand in the same tree, outside testmgr's path rewriting, printing
`argv0 canary ok 42`.
