---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This expectation records a REFUSAL** (TypeError). Before treating a converged bisect range as an accusation, check whether the named commit IMPLEMENTED the thing being refused -- a feature landing makes its own refusal test go red, and the bisect converges on it correctly. Not a verdict; the tool cannot decide this one.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_variant_operand_arith_dunders.npy red at 39d4afb022ce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T12:49:48Z
- **Test source:** test/test_nilpy_variant_operand_arith_dunders.npy test/test_nilpy_variant_operand_arith_dunders.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_variant_operand_arith_dunders.npy'` at 39d4afb022ce9a8f98f30f7a7202ccfa803b4d6f

## Range
> **The named sha `39d4afb022ce` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `39d4afb022ce`, last good `6b59df667fe4`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3793693/test_nilpy_vararith26  [code=1368033B  data=58560B  bss=43260B  procs=2021]
Unhandled exception: TypeError: comparison not supported between these instances (no __lt__/__le__/__gt__/__ge__)
--- test/test_nilpy_variant_operand_arith_dunders.expected	2026-08-09 00:37:48.089291330 +0200
+++ -	2026-08-27 14:40:21.930506396 +0200
@@ -5,9 +5,3 @@
 fdiv  3
 mod   1
 pow   49
-lt    False
-radd  ('radd', 3, 4)
-bare  TypeError
-nums  7 3 10 2.5 2 1 25
-strs  xy
-lists [1, 2] [1, 1]

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
