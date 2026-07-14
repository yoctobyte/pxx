---
prio: 70
---

# regression: test-core#src:test/test_widechar_to_utf8_b319.pas red at d94db8d6b0cc (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host borg). Untriaged.
- **Found:** 2026-07-13T21:19:49Z
- **Test source:** test/test_widechar_to_utf8_b319.pas

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_widechar_to_utf8_b319.pas'` at d94db8d6b0ccc8a1ce8441e7104293aeff071199

## Range
bad `d94db8d6b0cc`, last good `9daabff94650`, 16 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2631929/test_widechar_utf8_b31926  [code=51222B  data=592B  bss=9472B  procs=98]

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
