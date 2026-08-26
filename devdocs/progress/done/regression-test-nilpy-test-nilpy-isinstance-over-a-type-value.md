---
prio: 70
track: N
status: done
owner: frank1
---

> **Track guessed as N** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **origin/dev has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_isinstance_over_a_type_value.npy red at 99f1dc81a039 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-26T07:38:43Z
- **Test source:** test/test_nilpy_isinstance_over_a_type_value.npy test/test_nilpy_isinstance_over_a_type_value.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_isinstance_over_a_type_value.npy'` at 99f1dc81a039d8785db504b9f9b8917cf4e59783

## Range
> **The named sha `99f1dc81a039` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `99f1dc81a039`, last good `43b46283325f`, 54 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
Segmentation fault
(tail)
ok: /tmp/testmgr-scratch-701739/test_nilpy_isinstval26  [code=1248781B  data=55654B  bss=42972B  procs=1784]
Segmentation fault
--- test/test_nilpy_isinstance_over_a_type_value.expected	2026-08-11 12:48:08.167937701 +0200
+++ -	2026-08-26 09:25:56.065633060 +0200
@@ -1,11 +1,3 @@
 3 True
 True
 False
-False
-True
-True
-True
-True False
-True True True
-True True True
-True

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Root cause (frank1, 2026-08-26)

Not the aliased-type feature the test is named for — that half works. The
segfault is one line above it, in the arm that has always been there.

`PyParseIsinstance` has two roads to a user class: a VARIANT operand gets
`(tag = VT_OBJECT) and (pyvarobj(x) is C)`, and everything else gets a bare
`AN_IS_TEST`, which lowers to a VMT walk through the operand read as an object
pointer. A statically SCALAR operand took the second road with no guard on it,
so `isinstance("s", A)` walked a VMT at the string body. `isinstance(3, B)` is
the same crash one type over, and needs no alias at all — the test simply
reached the aliased spelling first.

The answer is known at compile time and it is False. `CanHoldInstance` now
folds the term for every kind that cannot hold an instance, and the unknown /
pointer-shaped kinds keep the test, so nothing that reached AN_IS_TEST before
stops reaching it.
- 2026-08-26 — resolved, commit PENDING-COMMIT.
