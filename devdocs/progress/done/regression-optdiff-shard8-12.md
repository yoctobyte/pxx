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
- 2026-08-04 — resolved, commit 814f2abfe.

## Attribution (Track T, 2026-08-04) — supersedes "resolved as stale"

A second session bisected it after the note above was written, so the culprit
IS named: **`2dbce8a2e`** — "fix(A/O): -O3 inline splice lost the +8 decay on a
string-literal arg". It was in the intervening commits; it just does not read
like a timezone fix, which is why the scan above did not match it.

Confirmed by building either side and comparing the two O-levels on the diffing
program, rather than by reading commit messages:

| build | -O0 | -O3 |
|---|---|---|
| `2dbce8a2e^` | `3cdda2778e1f` | **`e80496d848a3`** |
| HEAD | `3cdda2778e1f` | `3cdda2778e1f` |

## What the miscompile did — worth recording

At -O3 the timezone offset silently disappeared: every `local=` field came out
equal to `utc=`.

```
-O0:  1700000000 utc=2023-11-14 22:13:20 local=2023-11-14 23:13:20
-O3:  1700000000 utc=2023-11-14 22:13:20 local=2023-11-14 22:13:20
```

`test/ctime_localtime.c` exists precisely because `localtime()` used to be
`gmtime()` (feature-crtl-localtime-honours-the-timezone). So this was that bug
reappearing **at one optimization level only** — invisible to anyone testing at
-O0/-O2, wrong for everyone shipping -O3, and uncatchable by a functional test
because the program is correct. That is the argument for keeping the opt sweep.

So the classification is **fixed**, not stale: there was a real miscompile and
a real fix, and the reason neither was visible from the ticket is the next
paragraph.

## Why it sat for two days

The auto-filed range was **0 commits** — this run's `parent_tested` was the
tested sha, so the ledger had nothing to bisect and no idle bisect could ever
narrow it, while the stub text promised one. Third instance in this session;
filed as [[bug-t-empty-range-regression-cannot-be-bisected]].
