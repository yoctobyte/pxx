---
track: T
prio: 55
type: feature
summary: "`test-uforth` is in NO tier — the watcher has never run it, so the whole uforth corpus can rot silently between hand-runs. Enrol it in limited+full (NOT native: it is 46s and native is the tier dev boxes gate pushes on)."
status: done
owner: claude-T@plexus
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

## Log
- 2026-08-08 — resolved, commit 44ba3b1d8.

---

## Resolution (Track T, 2026-08-08) — commit `d6f83cebe`

Enrolled in **limited + full**, native untouched. Verified with `--list`:
native 1200 jobs / 0 uforth (unchanged), limited 1656 / 1, full 2178 / 1.
`test-uforth` PASSes in-tier in ~33 s.

**Cloned `yoctobyte/uforth` to `~/projects/uforth` on plexus** — the ticket
flagged this as the thing to check before closing, and it was absent, so the
enrolment would have been a silent SKIP.

### The ticket's own warning was the real work

"A SKIP that nobody notices is the failure mode to avoid here" — there were
**two** such holes, and enrolling without closing them buys a green that
tested nothing.

1. **A self-skipping target read as a pass.** `test-uforth` exits 0 when the
   tree is absent, so testmgr scored it PASS. It now detects a target that
   guarded its own precondition (anchored `^<target>: SKIP` in its log) and
   marks it `skip`, reported as SKIP.

   The first attempt used `skipped` and **turned a box lacking the checkout
   RED** — the exact false red this ticket forbids, because the run loop
   treats `skipped` as a dependency failure. `skip` is the pre-existing
   pass-equivalent did-not-run status and is now pass-equivalent for the gate
   too. Both paths verified: absent → SKIP + GREEN + exit 0; present → PASS.

2. **The corpus denominator concealed itself.** The Makefile loop `continue`d
   past absent corpora and reported `$ok/$ok` — always complete-looking.

### `UFORTH_CORPUS` cannot be satisfied by a clean clone — for the user

The ticket records 10/10 byte-identical. A fresh clone of `yoctobyte/uforth`
yields **4**. The six `tests/_drv_{c,file0,locals,string,t,x}.fth` files have
**never existed in uforth's git history** (`git log --all --diff-filter=A`
finds no `_drv_`), and are not in pxx either — they are local scratch on
whichever box did that work. Nothing here invented or regenerated them.

`make test-uforth` now says so out loud:

```
test-uforth: INCOMPLETE — 6 of 10 corpora absent from /home/neo/projects/uforth: ...
test-uforth: PASS — smoke + 4/10 corpora byte-identical to CPython (6 ABSENT)
```

**Committing those six to uforth upstream would take the enrolled signal from
4 corpora to 10 with no further pxx change.** That is the highest-value
follow-up here and it needs the box that has them.

### Known limitation, deliberately not widened

twatch maps `skip` → pass into tstate, so an absent-uforth box still reads
green at the tstate level. That is
[[bug-t-tstate-launders-skip-into-pass]], already filed; this ticket makes the
skip visible in the testmgr report, which is where its own gate lives.

`tests/_drv_file.fth` remains excluded by name pending
[[bug-nilpy-uforth-file-word-set-include-redefinition]] (the ANS FILE word
set) — unchanged by this ticket, and its own gate.
