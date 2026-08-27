---
prio: 70
track: N
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_star_operand_in_a_variant.npy red at 39d4afb022ce (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T12:49:48Z
- **Test source:** test/test_nilpy_star_operand_in_a_variant.npy test/test_nilpy_star_operand_in_a_variant.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_star_operand_in_a_variant.npy'` at 39d4afb022ce9a8f98f30f7a7202ccfa803b4d6f

## Range
> **The named sha `39d4afb022ce` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `39d4afb022ce`, last good `6b59df667fe4`, 12 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3793693/test_nilpy_starvariant26  [code=1280611B  data=56035B  bss=43292B  procs=1808]
Unhandled exception: TypeError: missing 510 required positional argument(s)
--- test/test_nilpy_star_operand_in_a_variant.expected	2026-08-15 08:40:36.359248422 +0200
+++ -	2026-08-27 14:42:25.734556755 +0200
@@ -7,8 +7,3 @@
 ('x', 'y')
 (1, 2, 3)
 (0, 1)
-xy
-(1, 2)
-17
-(4, 3)
-11 pq

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
