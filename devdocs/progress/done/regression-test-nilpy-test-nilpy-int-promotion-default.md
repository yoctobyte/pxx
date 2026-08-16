---
prio: 70
status: done
---

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-nilpy#src:test/test_nilpy_int_promotion_default.npy red at 459e96f985d1 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-16T09:13:26Z
- **Test source:** test/test_nilpy_int_promotion_default.npy test/test_nilpy_int_promotion_default.expected

## Repro
`tools/testmgr.py --tier full --job 'test-nilpy#src:test/test_nilpy_int_promotion_default.npy'` at 459e96f985d1588fac20836b151341cf7e967a61

## Range
bad `459e96f985d1`, last good `137a182ad46a`, 70 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1497482/test_nilpy_intpromo26  [code=2453212B  data=48768B  bss=13532B  procs=1913]
--- test/test_nilpy_int_promotion_default.expected	2026-08-07 07:30:11.503759064 +0200
+++ -	2026-08-16 11:03:03.818137813 +0200
@@ -40,10 +40,10 @@
 -4
 2
 15
+[]
+0
 [3000000000, 3000000001, 3000000002]
-4
-[3000000000, 3000000001, 3000000002]
-[3000000000, 3000000001, 3000000002]
+[]
 18446744073709551621 6148914691236517207 0
 5
 -6148914691236517207 0

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolved 2026-08-16 — the LIMIT was the one cell left 32-bit (Track N)

Not from any commit in the 70-commit range; confirmed pre-existing (the prompt's
earlier check at af588ad66^ agrees, and the mechanism is older than the range).

`for i in range(start, stop)` with no explicit step lowers to a Pascal AN_FOR
over `start .. stop-1`, and that limit node was built as a **tyInteger** binop —
a 4-byte cell — while the counter beside it is tyInt64. Any stop at or past 2^31
wrapped: `range(0, 3000000000)` got a limit of -1294967297, so the guard failed
on its first test and the loop ran ZERO times. Silent; the visible symptom is an
empty list where CPython prints three elements.

This is the third 64-bit cell the counted-loop lowering needs. The visible
counter and the variant path's hidden counter were both widened by
`bug-nilpy-for-range-loop-counter-is-32-bit-and-never-terminates`; the limit was
missed, which flipped the failure mode from never-terminating to never-entering
rather than fixing it. One concept, three sites — the usual shape.

Siblings probed against CPython and already correct: the stepped arm (literal
and runtime step), a negative step, range comprehensions, and variable bounds.

Fixed in b77240880. `test_nilpy_int_promotion_default` output is now
byte-identical to its `.expected`. Gate: `make compiler/pascal26` +
`tools/gate.sh quick` GREEN.
- 2026-08-16 — resolved, commit b2c371d98.
