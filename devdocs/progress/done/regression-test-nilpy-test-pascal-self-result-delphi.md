---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 3 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_pascal_self_result_delphi.pas@1 red at 23becd24b8e5 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-21T02:07:19Z
- **Test source:** test/test_pascal_self_result_delphi.pas

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_pascal_self_result_delphi.pas@1'` at 23becd24b8e5a952d29006a6efbab7e4a6068a0d

## Range
bad `23becd24b8e5`, last good `1b9b43e5b511`, 109 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:30: warning: bare own name 'CountDown' reads the result of parameterless function CountDown; write CountDown() for a recursive call, or Result to read the result
ok: /tmp/testmgr-scratch-2767347/test_pascal_self_result_delphi26  [code=58655B  data=1528B  bss=42428B  procs=119]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Not reproducible at HEAD — 2026-08-21 (agent-A)

Re-ran every expectation this job checks, against a self-hosted binary built at
`2c2ba74e4`, and all of them pass:

- `test_pascal_at_procvar_mode` — `-Mdelphi` gives TRUE TRUE FALSE TRUE FALSE,
  `-Mobjfpc` gives FALSE FALSE TRUE FALSE TRUE. The two runs DIFFER, which is
  the property the test exists to prove (a mode-ignoring build cannot pass it).
- `test_pascal_mode_switch_cli` — default `7 1`, `-Mdelphi` `42 4`,
  `-Mobjfpc` `7 1`, `-Mtp` `7 1`.
- `test_pascal_self_result_delphi` — `42 4 7 3 10` both as the source's own
  mode and with `-Mobjfpc` overridden by the source directive, and the "bare own
  name" warning does not fire (grep count 0), which is the @2 half.

### Why it is very likely not a code regression

All FOUR of these job entries went red together, in ONE job (test-nilpy), blamed
on `23becd24b8e5` — **a one-line ticket edit that touches no code**. The watcher's
full run at that point reports a wall of 3600.3s, i.e. it hit its hour limit; the
box was also running dev compiles. A job that dies at the wall marks every source
it owns as failing, and the blame lands on whatever commit was being tested.

That failure MODE is already filed as
[[bug-t-regressions-are-blamed-on-commits-that-touch-no-code]]. This ticket is
being closed as not-reproducible rather than fixed: there is nothing to fix in
the Pascal frontend, and a red that survives in the queue at prio 70 costs every
agent that pulls from the top. If it recurs on an idle box, reopen — that would
make it a real intermittent and worth a different hunt.
- 2026-08-21 — resolved, commit 9828f56a4.
