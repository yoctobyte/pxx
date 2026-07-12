---
prio: 70
---

# regression: test-smoke#11 red at 163ffea562fa (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-11T21:44:50Z
- **Test source:** compiler/compiler.pas test/bootstrap_features.pas

## Repro
`tools/testmgr.py --tier native --job 'test-smoke#11'` at 163ffea562fa3ae292765bc5ecf21fd2a0f45ac0

## Range
bad `163ffea562fa`, last good `7b95a7470ebc`, 8 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3482618/pascal26-self  [code=4101239B  data=132128B  bss=320541336B  procs=1789]
ok: /tmp/testmgr-scratch-3482618/pascal26-next  [code=4101239B  data=132128B  bss=320541336B  procs=1789]
ok: /tmp/testmgr-scratch-3482618/smoke_boot26  [code=32300B  data=232B  bss=8932B  procs=65]
ok: /tmp/testmgr-scratch-3482618/pascal26-fixedpoint  [code=4101239B  data=132128B  bss=320541336B  procs=1789]
cmp: EOF on /tmp/testmgr-scratch-3482618/pascal26-fixedpoint after byte 2371584, in line 1465

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage (2026-07-12, opus-night)
Transient, not a regression: the watcher itself re-tested the SAME SHA
(163ffea562fa) and went GREEN (full) with `FIXED:test-smoke#11` (tstate commit
d8bfac14); TSTATE.md shows no open regressions and everything through
7bf9e80393ed GREEN. The failing log's `cmp: EOF ... after byte 2371584` = a
TRUNCATED fixedpoint binary while self/next both built at full size — an
I/O-pressure artifact (the range contained the accidental 1450-file IDF
build-tree commit + its removal, i.e. heavy checkout churn on the same box),
same family as [[project_borg_red_harness_race_not_regression]]. No commit in
the range touches compiler/ at all (lib/rtl DNS, examples/esp32, tickets,
Makefile lib-test lines), so a genuine self-host regression was not possible
from source. Closing as transient-fixed.
- 2026-07-12 — resolved, commit d8bfac14.
