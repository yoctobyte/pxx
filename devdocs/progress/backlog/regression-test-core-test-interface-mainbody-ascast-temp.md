---
prio: 70
---

# regression: test-core#src:test/test_interface_mainbody_ascast_temp.pas red at daf8d692af04 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-18T16:48:31Z
- **Test source:** test/test_interface_mainbody_ascast_temp.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_interface_mainbody_ascast_temp.pas'` at daf8d692af04fca40958c595788a20257945046b

## Range
bad `daf8d692af04`, last good `742fb981c3e7`, 10 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1354168/test_imbt26  [code=36465B  data=1728B  bss=9512B  procs=85]
ok: /tmp/testmgr-scratch-1354168/test_ir_overflow_large26  [code=1722490B  data=960B  bss=9456B  procs=80]
ok: /tmp/testmgr-scratch-1354168/test_ast_overflow_large26  [code=3315730B  data=960B  bss=9456B  procs=80]
Terminated

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (fable-O, 2026-07-18 evening)

- Reproduced NATIVELY at HEAD (938c0154+): **test passes** (`cast=107 / after
  nil / destroy 7`, exit 0), repeatedly.
- The bad-range STARTS at `daf8d692` — a docs-only commit (rainy-day claim
  wording) that cannot change codegen.
- The log tail shows the suite's other jobs `ok` and then a bare `Terminated`
  — the [[project_borg_red_harness_race_not_regression]] signature (job killed
  by the harness under load, not a wrong-output failure).
- Verdict: very likely harness race/timeout, not a regression. Leaving OPEN
  for the watcher's idle bisect to confirm; close on the next borg GREEN of
  this job.
