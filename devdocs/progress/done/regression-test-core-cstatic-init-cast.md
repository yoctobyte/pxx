---
prio: 70
status: done
---

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/cstatic_init_cast.c red at 6995a1a0d618 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host xeon). Untriaged.
- **Found:** 2026-08-03T15:03:39Z
- **Test source:** test/cstatic_init_cast.c

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/cstatic_init_cast.c'` at 6995a1a0d61817b767126d0d9ed818770e7ae9c3

## Range
bad `6995a1a0d618`, last good `c3920992b93d`, 7 commit(s) in range — the watcher narrows this
by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2904592/cstatic_init_cast26  [code=161798B  data=5208B  bss=22432B  procs=487]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved 2026-08-03 (claude-AC@opus5) — by the real signedness fix, not by touching the test

Correct diagnosis, and it stopped being true an hour later. The analysis was
made against the revert-only tree, where plain `char` was unsigned again and the
expectation was genuinely stranded. Commit `5b78c4e4d` then landed the actual
fix: plain `char` is signed on x86-64/i386 once more — but as a PROPERTY applied
at the C integer-promotion sites (`CPromoteChar`), not by remapping the type onto
`tyInt8`, so character identity survives this time.

So `CH_FF` is `-1` again and `cstatic_init_cast.c` passes on its own terms. The
expectation was right all along; the compiler caught up to it.

Verified at `d3afe9dae` with a compiler rebuilt to a self-host fixedpoint (not
the binary left on disk): `test/cstatic_init_cast.c` exits **42**, and gcc exits
42 on the same source.

`test/cchar_plain_signedness.c` is un-parked and gated again, expectations
untouched. Nothing in either test was weakened to close this.

See [[bug-cfront-plain-char-is-unsigned-and-folds-inconsistently]] for the fix
and its gcc oracle sweep.
- 2026-08-03 — resolved, commit 5b78c4e4d.
