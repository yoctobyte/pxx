---
prio: 70
---

# regression: test-core#src:test/test_string_to_pchar_auto.pas red at 8997639f144f (auto-filed by twatch)

- **Type:** NOT a regression — the shared-/tmp SQLite race.
- **Status:** done — fixed 2026-07-13 in ad5d9c89.
- **Found:** 2026-07-13T01:51:35Z
- **Test source:** test/test_string_to_pchar_auto.pas

## Repro
`tools/testmgr.py --tier full --job 'test-core#src:test/test_string_to_pchar_auto.pas'` at 8997639f144fc690145e51c980d5c50b94986a89

## Range
bad `8997639f144f`, last good `8997639f144f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2417024/string_to_pchar_auto26  [code=48921B  data=1488B  bss=9520B  procs=578]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## CLOSED 2026-07-13 — same shared-/tmp race, fixed in ad5d9c89

`test_string_to_pchar_auto.pas` hardcoded its SQLite database path
(`/tmp/test_string_to_pchar_auto26.db`). testmgr runs core jobs in PARALLEL, and optdiff runs
the -O0/-O2/-O3 builds of one source CONCURRENTLY — so runs collided on a single database
file, and the resulting output difference was reported as a failure.

Note the "log tail" the watcher captured: it shows a SUCCESSFUL compile and nothing else.
That is what a race looks like in a report — the signal is the absence of a real error.

Fixed together with its two siblings (`test_sqlite_crud.pas`, `test_sqlite_crud_lazy.pas`)
in ad5d9c89: the DB path now comes from `ParamStr(0)`, which is unique per binary. They were
all fixed at once precisely so this ticket would not re-file itself from the next sibling
under a new SHA.

Same family as [[regression-optdiff-shard4-6]] and
[[project_borg_red_harness_race_not_regression]].

Verified: test-core green, `--tier opt` 11/11 GREEN, `--tier full` 1214/1214 GREEN.
