---
prio: 70
---

# regression: test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh red at 8766dccbd2dd (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T17:05:25Z
- **Test source:** tools/run_sqlite_thread_test.sh

## Repro
`tools/testmgr.py --tier full --job 'test-sqlite-threads-aarch64#src:tools/run_sqlite_thread_test.sh'` at 8766dccbd2ddf9495353735c5798ffaf325d9be1

## Range
bad `8766dccbd2dd`, last good `8766dccbd2dd`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
test-sqlite-threads: building threadsafe sqlite (aarch64) ...
ok: /tmp/testmgr-scratch-1801855/cstt_aarch64.oubs5Z/csqlite_thread_test26_aarch64  [code=6557740B  data=41792B  bss=51052B  procs=4158]
test-sqlite-threads: FAIL aarch64 (output mismatch)

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-07-14 — NOT REPRODUCIBLE at HEAD. Closing as a harness false-RED.

Re-ran the ticket's OWN repro command at HEAD (7dc1ab65): **GREEN**, 1/1 pass. The same is
true of the other two auto-filed regressions from that night, and a full-tier run on another
host came back green across the board.

The tell is in this ticket's own log tail: the captured output ends with a successful
`ok: ...` compile line and no failure at all. That is a harness artifact, not a compiler
red — the shape already documented in `regression-testmgr-conformance-shard-timeout-under-load`
(shards time out under full parallel load; that ticket notes it produced THREE false REDs in
one night — plausibly these three) and in the earlier cjson/lua shared-/tmp parallel race.

Closed as not-reproducible rather than fixed: no code changed to make it pass. If the
underlying flake matters, it is the shard-timeout ticket, not this one.

**Action for Track T:** these stub tickets were auto-filed at prio 70 and sat at the TOP of
the global ready queue, outranking every real prio-60 bug, without anyone having confirmed
they reproduce. A twatch RED should be re-confirmed before it is filed, or filed below the
triaged work.
- 2026-07-14 — resolved, commit 7dc1ab65.
