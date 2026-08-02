---
summary: "tools/gate.sh: pgrep -fc prints 0 AND exits 1, so `|| echo 0` makes others=\"0\\n0\" and every gate run emits a bogus 'integer expression expected' error"
type: bug
track: T
prio: 25
---

# `gate.sh` prints a spurious `integer expression expected` on every run

- **Type:** bug (tooling, cosmetic) — **Track T**
- **Opened:** 2026-08-01, seen while running `tools/gate.sh quick` for a Track
  A/N change. Filed rather than fixed: `tools/gate.sh` is Track T's file, and
  T owns the tool.

## Symptom

Every invocation, on an idle box:

```
gate: mode=quick  logs=/tmp/pxx-gate-3730778
tools/gate.sh: line 34: [: 0
0: integer expression expected
gate: box idle-ish (load 2.40)
```

## Cause

`note_contention()` (`tools/gate.sh:30`):

```sh
others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null || echo 0)
```

When nothing matches, `pgrep -fc` **prints `0` and exits 1**. Both halves of the
`||` therefore run, so `others` becomes the two-line string `"0\n0"`, and
`[ "${others:-0}" -gt 0 ]` on line 34 fails with `integer expression expected`.

## Impact

Cosmetic only, but worth fixing: the test errors out to the *else* branch, which
is the correct answer when nothing is running, so contention detection still
behaves right in the idle case. Two real costs:

1. Every gate run prints what looks like a script error, which is noise in
   exactly the output an agent reads to decide green/red.
2. It has never been exercised in the non-idle case here — if `pgrep -fc`
   returns a real count it exits 0, `others` is a clean number and the warning
   works. So the branch that matters is fine; only the common path is broken.

## Fix shape

Drop the `|| echo 0` (pgrep already prints `0`), or normalise:

```sh
others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null | head -1)
others=${others:-0}
```

## Gate

`tools/gate.sh quick` on an idle box prints no `[:` error, and still prints the
Track T contention warning when a `testmgr.py`/`twatch.py` process is running
(check both branches — the idle one is the regression here).

## Log
- 2026-08-02 — resolved, commit 07467a16f.
