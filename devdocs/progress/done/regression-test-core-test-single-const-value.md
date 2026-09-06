---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh test_single_const26 "$(/tmp/test_single_const26)" "$(printf '1 2.5000\n2 0.5000\n3 -1.5000\n4 1.500`. The job's own `src` (`test/test_single_const_value.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 1 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_single_const_value.pas at 74526018b122 in step 2/2, `tools/expect_same.sh test_single_const26 "$(/tmp/test_single_const26)" "$(printf '1 2.5000\n2 0.5000\n3 -1.5000\n4 1.50…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T14:55:02Z
- **Test source:** test/test_single_const_value.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_single_const26 "$(/tmp/test_single_const26)" "$(printf '1 2.5000\n2 0.5000\n3 -1.5000\n4 1.5000\n5 0.00 -1.50 2.50\n6 TRUE')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_single_const_value.pas'` at 74526018b122848d8763c96fcad7c9ab2a5c7c7a

## Range
> **The named sha `74526018b122` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `74526018b122`, last good `47aac577a587`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3030466/test_single_const26  [code=69400B  data=3072B  bss=43568B  procs=136]
expect_same: MISMATCH [test_single_const26]
--- expected
+++ actual
@@ -2,5 +2,5 @@
 2 0.5000
 3 -1.5000
 4 1.5000
-5 0.00 -1.50 2.50
-6 TRUE
+5 0.00 0.00 0.00
+6 FALSE

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Resolution — 2026-09-06, frankD (Track P, not T; the fallback lane was right to distrust itself)

**One character wide.** `RegisterVarInitElem`, added by b612f30e8 to route a
`var` initializer element to LocalInit* or PendingInit*, declared its value
parameter `val` as **Integer**. `PendingInitVal` and `LocalInitVal` are both
`array of Int64`, and a float element arrives as `ExDecDoubleToBits`' full IEEE
pattern, so the narrowing threw away every high word — `35.75` read back `0.00`
(its low 32 bits are exactly zero) and `6000000000` read back `1705032704`
(= it mod 2^32). Fixed by widening the parameter; the declaration is now split
across two lines so `val`'s width is stated alone and cannot be re-absorbed into
the Integer run by a later edit.

**The commit that broke these was gated green and the gate was not lying.**
`gate.sh quick` does not run `test-core`, so all three of these rows — and the
fixture the same commit added — sat outside it. Worse, the new fixture could not
have caught this at any width: every element it asserted was a string, a small
integer or a class reference, and all of those survive a truncation to 32 bits
intact. It has width rows now, global and local, with values CHOSEN so
truncation is not silent (35.75's low word is zero; 1705032704 is nowhere near
6000000000), and the narrowing was re-applied to confirm they fail.

**The change was only ever meant to pass the global path through unchanged, and
that is the whole lesson**: the three red rows are all GLOBAL. A helper extracted
from N call sites re-declares every parameter's type, and a type that was
implicit in the old inline code — `initVal: Int64`, assigned straight into an
Int64 slot — becomes an explicit choice nobody re-derives.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
