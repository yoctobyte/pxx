---
prio: 70
track: T
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 12 of 4 is `tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nope`. The job's own `src` (`test/test_string_n_container_strides.pas`, 3 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_string_n_container_strides.pas at 71a66c7d1437 in step 12/4, `tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nop…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-03T10:47:27Z
- **Test source:** test/test_string_n_container_strides.pas test/test_shortstring_byte_prefix.pas +1
- **Failing step:** line 12 of 4 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh test_strn_container26 "$(/tmp/test_strn_container26)" "$(printf 'openp1 1\nopenp2 1\nopenp20 1\nopenvals 1\ndyn1d 1\ndyn2d 1\ndyn2dvals 1\nguard 1')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_string_n_container_strides.pas'` at 71a66c7d14374aa793b9a200f23c41626c1d2879

## Range
> **The named sha `71a66c7d1437` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `71a66c7d1437`, last good `5d083bd91f9a`, 1 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-3917500/test_strn_container26  [code=73496B  data=3280B  bss=44296B  procs=138]
ok: /tmp/testmgr-scratch-3917500/test_ssbp_short26  [code=69400B  data=3304B  bss=43556B  procs=134]
expect_same: MISMATCH [test_strn_container26]
--- expected
+++ actual
@@ -4,5 +4,5 @@
 openvals   1
 dyn1d      1
 dyn2d      1
-dyn2dvals  1
+dyn2dvals  0
 guard      1

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*


## RESOLVED (frankB, 2026-09-03) — my regression, and the cause is a THIRD copy of one decision

**Re-laned A** (the fallback said T because the failing step named no owner; the
defect is in `ir_codegen.inc`).

`dyn2dvals` went 1 -> 0 at `18b92fac9`, which is mine: it rounded a frozen
string's slot size up to the prefix's alignment, so `string[10]` went 18 -> 24
bytes. That exposed a latent UNDER-ALLOCATION.

### The three copies

The per-element size of a dynamic array is decided in three places:

1. `DynElemSize` (`ir.inc`) — the INDEX path. Takes a capacity and has always
   asked `FrozenStrSlotSize`. Correct.
2. `GetOrAllocNodeDynDesc` / `GetOrAllocSymRTTI` (`ir_codegen.inc`) — the
   portable descriptor every CROSS backend hands to `PXXDynSetLen`. Asked
   `TypeStorageSize`, which reports a POINTER WIDTH for a frozen string.
3. x86-64's INLINE `IR_SETLEN_DYN` arm — its own `TypeSlotSize(slBaseTk)`, same
   pointer width, and its own copy of the descriptor build.

So SetLength allocated 8 bytes per element for a row the index path strides by
24, and the last element of every row was written past the end of its own block.

### Why it passed before, MEASURED rather than reasoned

Rebuilt the pre-`18b92fac9` compiler and measured the block, which is the part I
would otherwise have guessed wrong:

| | element stride | bytes needed for 3 | block actually allocated |
| --- | --- | --- | --- |
| before | 18 | 54 | **56** |
| after | 24 | 72 | 56 (now 104) |

The allocation was computed from 8 bytes/element and the allocator's bucket
rounding handed back 56 anyway — which happened to cover 54 and does not cover
72. **The under-allocation was there the whole time; the padding is what pushed
the overrun past the rounding.** `[r0c2]` and `[r1c2]` came back blank while
`[r2c2]` (the last row, nothing after it) was fine.

### The fix

One `SetLenDynElemSize`, asked by the portable descriptor and by the x86-64
inline arm, so the two cannot disagree again. The INDEX path's `DynElemSize`
stays where it is; collapsing all three wants the descriptor machinery reworked
and is not this fix — recorded in the comment so the count is visible to whoever
does.

### Verified

All eight rows green, six targets: x86-64, i386, aarch64, arm32, riscv32,
xtensa. Row gap for a 3-element row of `string[10]` is 104 bytes after
(3 x 24 + 16 header, bucketed), 56 before.

### Filed

[[bug-a-a-field-rooted-array-of-array-of-string-n-indexes-as-a-char]] — a
FIELD-rooted target has no symbol to carry the capacity, so its frozen element
still gets the kind-only size. Left unfixed deliberately: `r.matrix[0][0] := 'a0'`
does not compile at all (the second index resolves as a CHARACTER index), so
there is nothing to measure a fix against.
- 2026-09-03 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
