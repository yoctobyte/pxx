---
summary: "borg's enrolment BASELINE:16 red at d4f170a4e7fb is at least three populations — 7 wasm32 RUNNER-ABSENT (fixed), 3+ blocked on missing 32-bit dev libs (needs root), and a residual that may be the tree. Undifferentiated, the whole 16 reads as a tree regression."
type: bug
track: T
prio: 45
status: backlog
owner: claude@borg
---

# borg's enrolment baseline is three populations, and only one is a finding

- **Type:** bug (Track T — host enrolment / triage)
- **Found:** 2026-09-11, enrolling borg as the watcher host after seven's retirement.

## What happened

T stopped publishing: `seven` was retired into `plexus` at 16:29Z on 2026-09-11
and plexus has not run since 2026-08-30 (it is the dev box; the owner's
2026-09-01 directive says T deliberately does not run there). borg was
re-enrolled the same evening and published its first full as

```
tstate(borg): d4f170a4e7fb RED (full) BASELINE:16 red
```

A host with no prior job map has no baseline to diff against, so all 16 are
recorded as NEW-RED. **That is correct behaviour and a trap for the reader**:
the report is indistinguishable from a tree that broke 16 ways this evening.

## The split, measured

| n | population | evidence | status |
| --- | --- | --- | --- |
| 7 | wasm32 `RUNNER-ABSENT` | report's own `toolchain: … wasmtime=ABSENT`; every failure text reads `wasmtime not found, so target 'wasm32' was NOT RUN` | **fixed** — wasmtime 48.0.1 installed to `~/.local/bin`, matching the version seven reported. Gone from the next run's red list. |
| 3 | no 32-bit dev libs | `gcc -m32` cannot link here: `cannot find Scrt1.o`, `cannot find -lgcc`, `bits/libc-header-start.h: No such file`. Hits `test-emit-obj#00/#01/#02` | **needs root** — `apt install gcc-multilib libc6-dev-i386`, with the owner |
| 2 | same cause, other direction | `test-c-abi-mixed-link` / `test-record-abi-mixed-link` SKIP i386 on the recipes' own `gcc -m32` probe — scored passlike, invisible in a GREEN | same fix |
| ? | residual | `lib-test#src:tools/crtl_reachability.py`, `test-core#c_crtl_wait.c`, `test-core#c_pty_family.c`, `demos#00`, `tools-devtest#00`, `test-selfcompile-odiff#00` | **the only finding**, and not yet separated from the row below |

## The row that makes the residual hard: the toolchain INVERTED

seven's last report and borg's first, side by side:

| | seven (2026-09-11T16:28Z) | borg (2026-09-11T19:51Z) |
| --- | --- | --- |
| gcc | 15.2.0 | **13.3.0** |
| qemu | 10.2.1 | **8.2.2** |
| git | 2.53.0 | **2.43.0** |
| kernel | 7.0.0-31 | 7.0.0-29 |

The host running T is now two toolchain generations OLDER than the box every
current expectation was tuned against — and `meta/hosts.json` shows seven itself
was on gcc 13.3.0 until 2026-09-05, so the fleet has already moved once in the
other direction. Any differential probe against the **gcc oracle** now answers
about a different gcc than it did last week, and nothing in the harness says so.

`crtl_reachability`'s failure text is exactly the shape that predicts:
`conflicting types for typedef 'int64_t' — a repeated typedef must name the same
type`, from headers resolved out of the host `/usr/include`. That is
`track-t.md`'s own host-coupling rule, whose oracle is `ldd`, not the shape of
the assertion.

**So the residual cannot be triaged as tree defects until the two host gaps are
closed and one more full has run.** Ordering matters: fixing the host first
costs one sweep; triaging first costs a wrong diagnosis per job.

## Why this is filed as a bug and not a note

Two of the three populations were produced by conditions
`tools/twatch-setup.sh` called READY. That half is fixed in the same change as
this ticket — the script now derives its runner list from
`twatch.RUNNER_BINARIES` (it named four qemu binaries; the constant names seven,
and the three it omitted included wasmtime) and probes `gcc -m32` with the
recipes' own command. What is left here is the triage, which is not automatable:
deciding which of six residual reds are the tree.

## Next step

1. `apt install gcc-multilib libc6-dev-i386` (root; with the owner).
2. One full tier on borg, then diff its red set against this baseline.
3. Whatever is still red is the finding — triage it as host-coupling first
   (`ldd` the built test before reading the assertion), not as a regression.
