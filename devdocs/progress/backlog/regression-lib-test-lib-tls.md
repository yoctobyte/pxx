---
prio: 70
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_tls.pas red at 459e96f985d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T09:13:26Z
- **Test source:** test/lib_tls.pas

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_tls.pas'` at 459e96f985d1588fac20836b151341cf7e967a61

## Range
bad `459e96f985d1`, last good `137a182ad46a`, 70 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1497482/lib_tls  [code=252676B  data=11228B  bss=43836B  procs=614]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Triage 2026-08-16 — NOT REPRODUCIBLE natively at HEAD (Track A/P pass)

Built and ran at 341dbf99f on this box: compiles clean and prints all 14 `=ok`
lines, exit 0. The watcher's own log tail shows a clean `ok:` compile line and
no failing assertion, so the job failed at RUN time, not compile time.

`lib_tls.pas` carries a real loopback socket round-trip (bind/connect on a live
port), which makes it the one test in this pair that can fail for reasons that
are not the compiler — a busy port or a sandboxed network on the watcher host.
Left open rather than resolved: needs a re-run on plexus (the failing host) to
say transient vs host-specific. If it comes back green there, close it; if it
stays red only on plexus, it is a Track T environment item, not a compiler bug.
