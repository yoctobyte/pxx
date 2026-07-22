---
prio: 70
---

# -O3 differential: test_stack_frame_intrinsics_b270.pas (optdiff, persistent)

- **Type:** bug (optimization differential). **Track O → Track A file-ownership**
  (`-O3` pass / codegen). Filed by Track T; T owns the tool, not the bug.
- **Found:** 2026-07-18, re-filed consolidated 2026-07-20.
- **Test source:** `tools/optdiff.sh`

## What
`tools/optdiff.sh` reports a stdout/rc mismatch between `-O0` and `-O3` for
`test/test_stack_frame_intrinsics_b270.pas`:

```
OPT DIFF -O3: test/test_stack_frame_intrinsics_b270.pas (rc 0 vs 0)
optdiff shard N/6: pass=175 skip=21 diff=1
```

`rc 0 vs 0` — both runs exit clean, so the divergence is in **stdout**, not a
crash. `-O2` is not implicated in these reports; only `-O3`.

## Why this is one ticket, not six
This supersedes `regression-optdiff-shard0-6` and `regression-optdiff-shard5-6`,
which were auto-filed stubs naming the *shard* rather than the failing test.
Both name the same program, and shard0 recurred at four separate shas
(`6ba85512ab67`, `27b4fd840f7a`, `0178c3622bd7`, `69f7bda93ac4`). Every one was
recorded with `0 commit(s) in range` — the watcher's two-phase re-test of a
single sha, fixed in `ed6063f5`. So the shard/sha in those stubs carried no
information: this is a **persistent** `-O3` differential, not a regression
introduced by any one commit, and it needs a root-cause fix rather than a
bisect.

## Repro
```
tools/optdiff.sh --only test/test_stack_frame_intrinsics_b270.pas
# or via the manager:
tools/testmgr.py --tier opt --job 'optdiff#shard0/6'
```

## Status / next step
NOT reconfirmed at current HEAD — the checkout used for triage could not build
the compiler (stale seed vs post-pull sources), so no local repro was run. First
action for whoever picks this up: confirm it still diffs at HEAD, then diff the
`-O3` output against `-O0` to find which intrinsic/stack-frame value changes.
If it no longer reproduces, close it — the last confirmed sighting is
2026-07-18.

## Note on the `Terminated` line
The captured log tail begins with `Terminated`, i.e. the shard was killed
(timeout / harness stop) around the same run. Worth ruling out that the reported
diff is an artifact of a truncated run before digging into codegen.

## Log
- 2026-07-22 — Reconfirm attempt at HEAD (79ef4cf6+): full `tools/optdiff.sh`
  sweep = pass=1065 skip=165 **diff=0**; manual `-O0` vs `-O3` on
  test_stack_frame_intrinsics_b270.pas byte-identical, rc 0/0, and 5 repeat
  `-O3` runs hash-identical (deterministic). Last confirmed sighting was
  2026-07-18; many -O3-adjacent fixes landed since. Closing per the ticket's
  own instruction. If the watcher re-reports it, reopen with the failing
  stdout diff attached.
- 2026-07-22 — resolved, commit 79ef4cf6.
