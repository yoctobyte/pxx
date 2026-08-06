---
prio: 70
status: done
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_list_mutators_return_none.npy red at 9294bce2c800 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-06T08:04:09Z
- **Test source:** test/test_nilpy_list_mutators_return_none.npy test/test_nilpy_list_mutators_return_none.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_list_mutators_return_none.npy'` at 9294bce2c800eaa1dc7242e6ffd01120aaa20ca7

## Range
bad `9294bce2c800`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:39: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
(tail)
pascal26:39: error: Nil Python: annotate the type / too dynamic [a=6 b=28]
  near:   ys    >>>  ys  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-06 — FIXED by 48150cd3b, closing

One of THREE regressions from `e8450c58d67e` ("augmented assignment truncated to
32 bits"), all cleared by the single fix in `48150cd3b`: the module-scope
token-shape arm that commit added noted `tyPromoInt64` for every `name += ...`
it saw, asserting "this name is an int" about targets that are not — a class
instance with `__iadd__`, and a **list**, where `+=` is an in-place extend.
`PyWiden(promo, class)` is an honest error, so the programs stopped compiling
with "annotate the type / too dynamic".

The causal link was checked, not assumed: the other two tests in this group
contain module-level `xs += [3, 4]` / `zs += xs` / `ss += ["q"]` / `ys += [4]`,
which is exactly the shape the unguarded note broke.

The watcher's own trail agrees — NEW-RED at the commit itself, STILL-RED through
every report of the day, FIXED at `733be33` (the first report after the fix
landed). Re-verified locally at HEAD with the exact watcher job, PASS.

Fix: the arm now notes promo only when the target is ALREADY KNOWN to be an
integer, deferring to a later round of the pre-pass fixpoint otherwise.
- 2026-08-06 — resolved, commit PENDING-COMMIT.
