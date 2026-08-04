---
prio: 70
status: done
owner: claude-AN
---

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: optdiff#shard8/12 red at 28eb1a105ddb (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-02T14:10:52Z
- **Test source:** tools/optdiff.sh

## Repro
`tools/testmgr.py --tier opt --job 'optdiff#shard8/12'` at 28eb1a105ddb027c2ee7b8e2240677c9433243d4

## Range
bad `28eb1a105ddb`, last good `unknown`, 0 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
OPT DIFF -O3: test/ctime_localtime.c (rc 0 vs 0)
Segmentation fault (core dumped)
optdiff shard 8/12: pass=100 skip=16 diff=1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Re-verified at HEAD 2026-08-04 — NO LONGER REPRODUCES

Checked at `b3ccf2f61` (self-hosted fixedpoint build, compiler sha256
a4d295ea83d4), which is 8 commits past the `28eb1a105ddb` this was filed
against — the stub's own banner asks for exactly this re-check.

- the ticket's repro line, run verbatim:
  `tools/testmgr.py --tier opt --job 'optdiff#shard8/12'` -> **GREEN**, 1/1 pass,
  61.2s. No segfault, no diff.
- the named test on its own: `test/ctime_localtime.c` built at -O0/-O1/-O2/-O3,
  all four exit 0 and all four produce IDENTICAL stdout, so the reported
  `diff=1` is gone too.

Resolved as stale rather than fixed: the signal was real when filed, but it was
never bisected (`last good unknown`, 0 commits in range) so there is no
identified culprit commit to name, and nothing in the eight intervening commits
is an obvious match. If it returns, the watcher will re-file it with a narrower
range — which is the right way for it to come back, rather than keeping an
unreproducible ticket open.
- 2026-08-04 — resolved, commit PENDING-COMMIT.
