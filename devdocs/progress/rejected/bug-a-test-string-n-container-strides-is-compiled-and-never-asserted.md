---
prio: 50
track: A
type: bug
status: rejected
summary: "RETRACTED by its author: the premise is FALSE. test_string_n_container_strides IS asserted -- the expect_same row keys on the BINARY name test_strn_container26, not the source path, so a grep for the source found the compile and not the compare. The one real half (`dyn2dvals` printing 0) was a live under-allocation and is fixed; see regression-test-core-test-string-n-container-strides."
---

# test_string_n_container_strides is compiled and never asserted

Makefile (~11114) builds `$(TESTTMP)/test_strn_container26` and the next line is
a comment introducing the NEXT test. No `tools/expect_same.sh` names it, so the
binary is produced and discarded. A compile error would be caught; nothing else.

Measured 2026-09-03, native x86-64:

```
             pinned (v401)   HEAD + frozen-layout fixes
openp1            0                    1
openp2            0                    1
openp20           0                    1
openvals          1                    1
dyn1d             1                    1
dyn2d             0                    1
dyn2dvals         0                    0     <-- still failing
guard             1                    1
```

The file's own comment ("5 of these 8 rows go 0 when built with the pinned
compiler") is accurate and the container-stride fixes it documents did land --
except `dyn2dvals`, the VALUES row for the inner dimension of
`array of array of string[N]`, which is 0 in every build measured. `dyn2d` (the
STRIDE row) passes, so the stride is right and what is written or read through
it is not.

TWO SEPARATE THINGS, and the wiring is the cheaper one:

1. **Wire the assertion.** Not with today's output -- that would bake
   `dyn2dvals 0` in as expected and make the suite green over a live defect.
   Wire it when the row is fixed, or wire it now with a comment naming this
   ticket if a partial row set is worth having sooner.
2. **Fix `dyn2dvals`.** Diagnose before assuming: the sibling causes in this
   family were DynElemSize asking TypeSlotSize, and AllocParam reading a stale
   LastTypeStrCap return channel.

Found while sweeping every test source that mentions both `string[` and
`SizeOf` for fallout from the frozen slot-size change; this file was the one
whose output nothing was comparing.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]


## RETRACTED (frankB, 2026-09-03) -- the grep answered a different question

`grep string_n_container_strides Makefile` returns exactly one row, the compile.
That reads as "nothing compares it" and it is not what the grep was asked: the
compare row names the BINARY, `test_strn_container26`, and it has been there all
along asserting `dyn2dvals 1`. The instrument did not error; it answered about a
literal string.

frankuser made the identical mistake on the identical rows about an hour later,
independently, which is what makes it a class rather than my slip: **a Makefile
test row is addressed by its OUTPUT name, so grep the binary, not the source.**

**The other half of this ticket was real.** `dyn2dvals` printing 0 was a genuine
under-allocation -- SetLength sized elements with `TypeStorageSize` (a pointer
width for a frozen string) while the index path strided by `FrozenStrSlotSize`,
and the allocator's bucket rounding had been hiding the shortfall until the
prefix padding at 18b92fac9 pushed the overrun past it. Diagnosed and fixed at
the root in [[regression-test-core-test-string-n-container-strides]], which is
where that work is recorded. Nothing here needs wiring: the row was always
wired, and it did its job.
