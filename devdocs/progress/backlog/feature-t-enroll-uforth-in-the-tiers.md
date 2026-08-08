---
track: T
prio: 55
type: feature
summary: "`test-uforth` is in NO tier — the watcher has never run it, so the whole uforth corpus can rot silently between hand-runs. Enrol it in limited+full (NOT native: it is 46s and native is the tier dev boxes gate pushes on)."
---

# Enrol `test-uforth` in the tiers — it is currently gated by nobody

Measured 2026-08-08, while clearing uforth's blocker chain:

```
$ grep -c uforth tools/testmgr.py
0
```

`test-uforth` appears in **no entry of `TIERS`**. The watcher has never run it.
Every uforth fix — five compiler bugs cleared today, taking the driver suite
from 2/11 to 10/11 byte-identical with CPython — is protected only by somebody
remembering to type `make test-uforth`.

This is the same hole `test-nilpy` was in until 2026-08-01, and the comment
recording that fix is right above where this one belongs:

> test-nilpy: MAINLINE and gated ... but it was in no tier at all — so 238 of
> the 309 .npy files the Makefile compiles were invisible to the watcher and
> `make test-nilpy` could be RED while the full tier reported GREEN

uforth is the Track N forcing corpus — ~4300 lines of unmodified Python plus a
layered `.UFO` stdlib, exercising closures, bound methods, `Callable` fields,
variant receivers, the pyeval bridge and dataclasses at once. It is the single
densest NilPy regression signal in the tree, and nothing runs it.

## Which tier — with the numbers

| what | wall |
| --- | --- |
| `make test-uforth`, smoke only (before today) | **15 s** |
| `make test-uforth`, smoke + 10 differential corpora (now) | **46 s** |

**limited + full, NOT native.** The `TIERS` comment is explicit that native is
the tier dev boxes gate their pushes on and the one number T must not inflate —
enrolling nilpy there took the fast verdict from ~104 s to ~235 s. 46 s is the
same order and does not belong there. Placement matches `test-nilpy` exactly.

If a fast uforth signal is wanted at native later, the pattern already exists:
a quick-tier canary (`test/quick_canary_nilpy.npy`, broad-not-deep, ~1 s)
rather than the whole corpus.

## Note: it SKIPS cleanly when the clone is absent

`test-uforth` exits 0 with `SKIP — no uforth tree at $(UFORTH_SRC)` when
`~/projects/uforth` is missing, and the corpus half also skips when there is no
`python3` to be the oracle. So enrolling it cannot turn a box red for lacking
the checkout — but it also means **the watcher box needs the clone for this to
be worth anything**. Check that before closing:

```
git clone git@github.com:yoctobyte/uforth ~/projects/uforth
```

A SKIP that nobody notices is the failure mode to avoid here; consider having
the tier report a skipped uforth distinctly from a passing one.

## Already done (not part of this ticket)

The corpus half landed with the uforth work: `make test-uforth` now runs
uforth's own `testje*.for` and `tests/_drv_*.fth` DIFFERENTIALLY — the same
`uforth.py` under CPython is the oracle, so there is nothing recorded to go
stale when uforth moves. 10/10 byte-identical today.

`tests/_drv_file.fth` is deliberately excluded by name (the ANS FILE word set,
[[bug-nilpy-uforth-file-word-set-include-redefinition]]); adding it back to
`UFORTH_CORPUS` is that ticket's gate.

## Gate

`tools/testmgr.py --tier limited` and `--tier full` both run and report the
uforth job; `--tier native` unchanged in composition and wall time.
