---
prio: 70
track: P
status: done
owner: claude-A
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_setlength_grow_capacity.pas red at 10dada0b7689 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-25T16:38:27Z
- **Test source:** test/test_setlength_grow_capacity.pas test/test_dynarray_concat_rejected.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_setlength_grow_capacity.pas'` at 10dada0b7689fee546516eec7ea90d1da4256053

## Range
bad `10dada0b7689`, last good `d20300d288eb`, 7 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1853321/test_setlength_grow_capacity26  [code=65250B  data=2016B  bss=42480B  procs=128]

```

## Diagnosis (Track A/P, 2026-08-25)

Not `test_setlength_grow_capacity` — that one is green (see the log tail: it
compiled `ok`). The job bundles a second source, and the red is
**`test/test_dynarray_concat_rejected.pas`** (Makefile 5830-5831).

It is a NEGATIVE test asserting `c := a + b` over two dynamic arrays is refused.
`f2bad72e9` (feature-p-dynamic-array-concatenation) deliberately made that
spelling COMPILE, as concatenation. The test was obsoleted by the feature and
should have been retargeted in that commit — the same move already made for
`test_chained_helper_member_fail.pas`.

## Fix

Retargeted the test to the arm that is still loud, keeping the original intent
(a meaningless arithmetic operator on a dynamic array must ERROR, never
miscompile into a pointer-add that segfaults). It now uses `c := a + n` — a `+`
with an array on only ONE side, which is the tightest condition on that
`ir.inc` arm and the exact boundary the concat feature moved. `-`, `*` and `div`
land on the same arm.

The positive side is covered by `test/test_dynamic_array_concatenation.pas`.
`tools/gate.sh quick` GREEN.
- 2026-08-25 — resolved, commit PENDING-COMMIT.
