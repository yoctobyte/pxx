---
track: T
prio: 45
type: bug
---

# Watcher and dev session on one box false-RED slow test-core jobs

- **Track:** T (test infra — false RED, costs a dev investigation)
- **Found:** 2026-07-19 by a Track A session, via tstate report
  `20260719T175151Z-e584d7b-borg.md`.

## Symptom

tstate reported NEW-RED at e584d7b4:

```
test-core#src:test/test_interface_mainbody_ascast_temp.pas
...
ok: /tmp/testmgr-scratch-4187991/test_imbt26  [code=36465B ...]
Terminated
```

The tell is `Terminated` with the compile line reading `ok` — a kill, not a
wrong result. The job passes standalone (`--tier native --job
'test-core#...ascast_temp.pas'` → GREEN, 111.5s), and the same dev session's
own `--tier full` at the same tree classified it "flaky (recovered on retry)".

## Cause (distinct from the existing shard tickets)

Not intra-run parallelism like
[[regression-testmgr-conformance-shard-timeout-under-load]] and
[[bug-t-qemu-conformance-false-timeout-under-load]] — those are one testmgr
oversubscribing itself. Here TWO testmgr processes from DIFFERENT checkouts
ran concurrently:

```
4168963 /usr/bin/python3 /home/rene/frankonpiler/tools/testmgr.py --tier full
4187991 /usr/bin/python3 /home/rene/trackt-watch/tools/testmgr.py --tier native
```

The watcher's dedicated clone and the dev checkout each size their own
parallelism to the whole box, so together they oversubscribe it ~2x. The jobs
that lose are the long ones: this test is 111.5s standalone, and the surviving
sibling in the same shell (`test_token_growth`, 12000 procs) is likewise slow.

## Why it matters

A false RED on a test named `..._ascast_temp` is expensive: the as-cast temp
lifetime bug is a REAL known landmine (layout-sensitive SIGSEGV, see
`project_interface_ascast_temp_lifetime_landmine`), so this specific job
false-REDing reads exactly like that landmine resurfacing and pulls a dev
session into a full investigation.

## Fix shapes (T's call)

- A cross-process lock or advisory token so the watcher defers while a dev
  testmgr is live on the same box (the xvfb lock is a precedent).
- Scale the timeout by observed load rather than wall-clock alone.
- Distinguish `Terminated` / exit 124 from a genuine failure in the report and
  auto-retry before declaring NEW-RED — the retry logic already exists in the
  dev path ("flaky, recovered on retry"); tstate's path did not apply it.
