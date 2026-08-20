---
prio: 70
---

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh red at 21117f415284 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-20T03:08:00Z
- **Test source:** tools/selfhost_fixedpoint.sh

## Repro
`tools/testmgr.py --tier native --job 'selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh'` at 21117f4152845a44e578a5eb04dc3af250a0b935

## Range
bad `21117f415284`, last good `8eb2ce583499`, 15 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
/tmp/testmgr-scratch-3918410/selfhost-fp-3919810/stage_2a /tmp/testmgr-scratch-3918410/selfhost-fp-3919810/tested differ: byte 97, line 1
(tail)
converged after 2 round(s) from pinned: the compiler reproduces itself
FAIL: the fixedpoint reached from PINNED differs from compiler/pascal26
      (both may self-reproduce — that is exactly the point: two distinct
       fixedpoints means the binary we test with is not the one these
       sources define. Local seed contamination, or a self-perpetuating
       miscompile.)
/tmp/testmgr-scratch-3918410/selfhost-fp-3919810/stage_2a /tmp/testmgr-scratch-3918410/selfhost-fp-3919810/tested differ: byte 97, line 1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Re-verified at HEAD — 2026-08-20 (sha `df9c970d4`, box plexus/frank1)

Does **not** reproduce. `tools/selfhost_fixedpoint.sh` run by hand in a fresh
bootstrap of `/home/neo/frank1`, 1m35s, exit 0, both halves green:

```
converged after 2 round(s) from pinned: the compiler reproduces itself
agrees with compiler/pascal26 (the binary the suite is testing with)
```

So the AGREEMENT half — the one the watcher reported red — passes here. Two
readings, and this run cannot tell them apart:

1. it was fixed in the 2 commits between `21117f415284` and HEAD, or
2. the red was **local seed contamination in the watcher's own clone**, which
   is one of the two causes the FAIL text itself names. That clone was
   mid-`--tier native` when plexus lost power at 05:50 on 2026-08-20 and its
   object store came back with 27 zero-length objects; a `compiler/pascal26`
   left behind by an interrupted run is exactly the "binary we test with is not
   the one these sources define" case.

**Leave this open** until Track T sweeps a clean clone at a sha ≥ HEAD. One
local green is evidence, not a close — and reading (2) means the same red can
come back the moment the daemon restarts on that tree without a rebuild.

Related, and probably NOT the same bug: `regression-test-core-compiler-4`
(threadsafe self-host) **does** reproduce at HEAD, with the same
`differ: byte 97, line 1` signature and a 32-byte data-section delta. Byte 97
is section-header territory, so the shared signature may only mean "the two
binaries differ in a section size", not "same cause". Do not merge the tickets
on the strength of that line alone.

## Log
- 2026-08-20 — auto-closed by the plexus watcher: `selfhost-fixedpoint#src:tools/selfhost_fixedpoint.sh` passes at 6e937a27b469 (tier native); it was red at 21117f415284. Reopening is by a fresh NEW-RED stub, since a second red is a second finding with its own range.
