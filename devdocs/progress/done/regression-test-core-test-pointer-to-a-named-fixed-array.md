---
prio: 70
track: P
status: done
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_pointer_to_a_named_fixed_array.pas red at ff07990984a0 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T20:47:38Z
- **Test source:** test/test_pointer_to_a_named_fixed_array.pas tools/expect_same.sh +1

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_pointer_to_a_named_fixed_array.pas'` at ff07990984a02632f8380d21d54ac26311a715b9

## Range
> **The named sha `ff07990984a0` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `ff07990984a0`, last good `4e883063f292`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-2155701/test_pfixarr26  [code=73496B  data=3656B  bss=42764B  procs=129]
expect_same: MISMATCH [test_pfixarr26]
--- expected
+++ actual
@@ -1,6 +1,6 @@
 int64  : 1000000000 1000000001 1000000002 1000000003 | 4 0 3 32
 lword  : 10 11 12 13 | 4 0 3 16
-lowbnd : 101 102 103 104 | 4 1 4 16
+lowbnd : 102 103 104 4314200 | 4 1 4 16
 record : 0/10/100 1/11/101 2/12/102 | 3 2 36
 whole  : 2 12 102
 2d     : 0 1 2 10 11 12 | 2 0 1 24

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## Fixed — frank-rust, 2026-08-30

**GREEN on the merged tree.** Ran the exact job's program at fixedpoint
`75a59e7ea507`: output matches `test_pointer_to_a_named_fixed_array.expected`
byte for byte, `lowbnd` row included.

I can name the mechanism rather than guess it, because I hit the identical
failure in my own working tree an hour later and it is in this ticket's own
log tail:

```
-lowbnd : 101 102 103 104      <- expected
+lowbnd : 102 103 104 4314200  <- one element past the start
```

That is the pointee's LOW BOUND not being subtracted. `ParseLValueAST`'s suffix
chain does that normalisation in its `DerefPtrArrayInfo` arm — and that arm sat
BELOW `else if IsNodeArray(node)`. So the moment `IsNodeArray` learned to answer
TRUE for `p^` over a pointer-to-array (`5d840acdd`, the correct and necessary
half of the fix), the earlier arm began claiming the node and the low-bound
subtraction stopped running. `array[0..3]` was unaffected — lo is 0 — which is
why only the `lowbnd` row moved and why it read as a narrow regression rather
than as the arm-ordering problem it is.

Fixed by moving the `DerefPtrArrayInfo` arm to the HEAD of that chain, above
every arm that dispatches on `tk`:
`bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds`.
Same root as the ticket it came from — every arm in both the parser's chain and
`IRLowerAddress`'s dispatches on a `tk` that, for this shape, is the ARRAY's
ELEMENT kind. Asking what the base IS has to come first.

`test/test_pointer_to_array_indexing.pas` carries a `array[1..4] of PChar` row
for exactly this, beside the `array[0..3]` rows that cannot catch it.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
