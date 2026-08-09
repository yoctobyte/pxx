---
track: T
prio: 45
type: bug
---

# T reports `test_nilpy_str_isnumeric_istitle` RED at full tier; not reproducible locally

`devdocs/progress/tstate/plexus.json` at 2026-08-09T08:30:09Z:

```
history[-1]: { sha: 0d6de0cbe, tier: "full",
               new_red: ["test-nilpy#src:test/test_nilpy_str_isnumeric_istitle.npy"] }
open_regressions[0]: { job: same, good: 4939f47ab, bad: 0d6de0cbe, range: 14 commits }
```

The test was added in `38b94a77d` (inside that range) together with the
`pystr_isnumeric` / `pystr_istitle` implementations.

## What was checked locally, at the same sha, clean tree

- `./compiler/pascal26 test/test_nilpy_str_isnumeric_istitle.npy` then
  `diff -u` against its `.expected` — **passes**, byte-identical.
- the full **`make test-nilpy`** — reached the recipe (log line 287) and
  **continued past it**; make halts on a failing recipe, so it passed there.
  The run went on to line 2043+ with no `make: *** Error`.
- `tools/gate.sh quick` — GREEN (self-host fixedpoint + testmgr quick),
  repeatedly, before and after.
- a whole-suite HEAD-vs-pinned sweep of all 106 `.npy` tests with `.expected`
  at this sha — **zero regressions**, 40 fixed.
- both files are committed and tracked (`git ls-files` confirms the `.npy` and
  the `.expected`).

So the red is not reproducible on this box.

## The one thing that looks explanatory, and does not hold up

`pin_shadow` at the same timestamp reports `unexpected: [
selfhost-fixedpoint#src:compiler/compiler.pas, test-nilpy#src:...isnumeric... ]`
with `would_pin: false`. A new-feature test failing under the PINNED compiler is
expected between landing and a re-pin, and `pin_shadow`'s own comments describe
the stale `selfhost-fixedpoint` key as a known orphan. That would explain the
shadow entry — but the `history` entry records it as a **`new_red` in the full
tier**, which is the real run, not the shadow. So the shadow explanation covers
only one of the two appearances.

## Why this is filed under T rather than N

Per CLAUDE.md, T owns the tool and never the bug — and a finding is normally
filed into the owning lane, which here would be N. It is filed under T instead
because the *finding itself* is a disagreement between T's verdict and the same
command run locally at the same sha, so the first question is whether the job's
attribution or its environment is right, not what the NilPy code does. If T
reproduces it with the failing output attached, re-file into N immediately and
this ticket closes.

**What would settle it:** the actual diff output from T's run of that recipe.
The tstate record carries the job name and shas but not the failing output, so
there is nothing to diagnose from — which may itself be worth improving.
