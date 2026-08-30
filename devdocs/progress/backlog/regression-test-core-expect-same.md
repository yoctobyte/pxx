---
prio: 70
track: T
---

> **Track T by default: no lane could be inferred** from `tools/expect_same.sh`. This is a FALLBACK, not a finding — nothing here says the defect is Track T's, only that the test source did not name an owner. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:tools/expect_same.sh@276 red at 9ced9bbc3e2d (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T03:16:01Z
- **Test source:** tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:tools/expect_same.sh@276'` at 9ced9bbc3e2d643dac51501c3324dc972ccdce7e

## Range
> **The named sha `9ced9bbc3e2d` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `9ced9bbc3e2d`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

## Log tail
```
pascal26: error: cannot read input file: /tmp/testmgr-scratch-4095178/cnest16/gmain.c
(tail)
pascal26: error: cannot read input file: /tmp/testmgr-scratch-4095178/cnest16/gmain.c

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
