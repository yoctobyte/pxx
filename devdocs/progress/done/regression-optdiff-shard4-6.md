---
prio: 70
---

# regression: optdiff#shard4/6 red at 6e0395e5495f (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). **NOT a codegen regression — a shared-/tmp race in the TEST.**
- **Status:** done — fixed 2026-07-13.
- **Found:** 2026-07-13T02:18:22Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard4/6'` at 6e0395e5495f72a8c046d8a88c77183f7989dcd2

## Range
bad `6e0395e5495f`, last good `6e0395e5495f`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O2: test/test_sqlite_crud.pas (rc 0 vs 0)
OPT DIFF -O3: test/test_sqlite_crud.pas (rc 0 vs 0)
optdiff shard 4/6: pass=146 skip=18 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## RESOLVED 2026-07-13 — it was never an optimization diff

The report blamed `6e0395e5` (an unrelated `absolute` fix) simply because that was the SHA
being tested. The give-away is in the log the watcher captured:

```
OPT DIFF -O2: test/test_sqlite_crud.pas (rc 0 vs 0)
```

**Same exit code, different output.** A real codegen difference at -O2 does not usually
leave rc identical and perturb only the bytes; a RACE does.

`test_sqlite_crud.pas` hardcoded its database path: `/tmp/test_sqlite_crud26.db`. optdiff
compiles one source at -O0/-O2/-O3 and runs the three binaries CONCURRENTLY — so all three
opened, DROP-TABLE'd and INSERT-ed into the SAME file. They clobbered each other, and the
differing output was reported as an optimization diff.

This is the same shared-/tmp race that bit cjson/lua
([[project_borg_red_harness_race_not_regression]]). Two SIBLING tests had it too, and would
have flaked next: `test_string_to_pchar_auto.pas` and `test_sqlite_crud_lazy.pas`.

Fix: derive the DB path from `ParamStr(0)` (argv[0]), which differs per opt-level binary, so
each run gets its own database. All three tests fixed together — leaving the siblings would
just have re-filed this ticket under a different SHA next week.

Verified: `optdiff#shard4/6` PASSES (3 consecutive runs), `--tier opt` 11/11 GREEN,
`make test` green.

**Lesson for the watcher's reports:** `rc N vs N` with differing output is a strong signal
for a race, not a miscompile. Worth surfacing in the report format — it would have saved the
triage.
