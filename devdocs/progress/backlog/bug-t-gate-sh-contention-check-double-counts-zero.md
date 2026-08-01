---
summary: "tools/gate.sh: the watcher-contention check prints a shell error on every run because `pgrep -c` emits 0 AND exits 1, so the `|| echo 0` fallback appends a second 0"
type: bug
track: T
prio: 25
---

# gate.sh contention check errors on every idle run

- **Type:** bug (Track T tooling, cosmetic but noisy) — **Track T**
- **Opened:** 2026-08-01, seen on every `tools/gate.sh quick` run this session.
  Filed rather than fixed: `tools/gate.sh` is Track T's file and this session
  held A+P+C+N.

## Symptom

Every gate run on an idle box prints a shell error before the real output:

```
gate: mode=quick  logs=/tmp/pxx-gate-16665
tools/gate.sh: line 34: [: 0
0: integer expression expected
gate: box idle-ish (load 2.38)
```

The gate itself is unaffected — it goes on to run and report correctly (that
run finished GREEN). It is noise, but it is noise on the one tool every track
is told to use for gating, so it reads as "something is wrong with my gate"
every single time.

## Cause

In `note_contention()`:

```sh
others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null || echo 0)
```

`pgrep -c` already prints `0` when nothing matches — and *also* exits 1. So the
`|| echo 0` fallback fires on top of the `0` pgrep already printed, and `others`
becomes the two-line string `"0\n0"`. The `[ "${others:-0}" -gt 0 ]` test then
fails with `integer expression expected`.

Because the test errors rather than evaluating true, the else-branch still runs
and the "box idle-ish" line is correct — which is why this has survived.

## Fix

Keep the exit status off the value, e.g.

```sh
others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null) || others=0
others=${others:-0}
```

Worth a glance at the `load=` line just below it for the same shape — that one
is fine today only because `cut` succeeds when `/proc/loadavg` exists.

## Gate

`tools/gate.sh quick` on an idle box prints no shell error, and the
contention branch still fires when a watcher IS running (test by starting a
`twatch.py` or by pointing the pattern at a running process).
