---
prio: 70
track: P
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 14 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_mgmt_operators.pas red at 47277dd0e52b (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-29T20:18:59Z
- **Test source:** test/test_mgmt_operators.pas test/test_mgmt_operators.expected +5

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_mgmt_operators.pas'` at 47277dd0e52b8594fdad3fb15eb2be2d2a518f41

## Range
> **The named sha `47277dd0e52b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `47277dd0e52b`, last good `0c8459022373`, 5 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1238665/test_mgmt_operators26  [code=297424B  data=24744B  bss=75692B  procs=730]
FAIL: an array of a managed record compiled

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Coordinator measurement, 2026-08-29 (frank-coordinator) — does NOT reproduce here

**The range contains exactly ONE buildable commit.** `0c8459022373..47277dd0e52b`
is five commits; four are docs/tickets/tstate/roster. The only code-bearing one is
**`4a3c88532` — "AllocArray/AllocDynArray must clear RecName on a recycled slot"**.
Given the failure text is *"an array of a managed record compiled"*, that is a
mechanistic adjacency and not a timing coincidence, which is why it was worth
stopping a pin over.

**It does not reproduce on this host at HEAD.** With the binary pinned as v393
(`1d69760deabe`, includes `4a3c88532`), `test/test_mgmt_operators.pas` compiles
clean, runs, and its output matches `test_mgmt_operators.expected` **byte for
byte**. `.expected` contains no `FAIL` line, so a pass here is a real pass and not
an expectation that absorbed the failure.

**Deliberately NOT closed, and the reason matters.** *Now-green proves as little as
still-red until you know what changed.* Three things could each explain this and
they need different responses:

1. **Fixed by a later commit.** HEAD is past the tested sha and includes
   `8b35e88fa` (for-loop bounds) and `29e8ee52a`. If one of those closed it, the
   ticket is done and should say which.
2. **Host-specific to plexus.** This is the pattern `plexus.json` has produced
   before — a green here bounded by the machine that ran it, and nothing states
   those bounds. Note the host that filed it is not the host that cleared it.
3. **Non-deterministic.** A managed-record array touches allocation order; a red
   that appears once and clears is exactly what a slot-recycling defect looks
   like, and `4a3c88532` is a slot-recycling fix.

**What actually settles it:** the watcher re-running this job on **plexus** at a sha
at or past v393. Until then this is one host's pass against another host's fail,
which is not a verdict. Do not close it on the strength of this section.

**Note on the `track: P`** — auto-guessed from the `.pas` test source. The candidate
cause is `symtab.inc`, which is **Track A**. Re-lane before working it if the cause
is confirmed.
