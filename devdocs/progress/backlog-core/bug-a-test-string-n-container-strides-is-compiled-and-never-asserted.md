---
prio: 50
track: A
type: bug
status: backlog
summary: "test_string_n_container_strides is COMPILED by the Makefile and never run or compared -- there is no expect_same line for it, only the compile -- and its `dyn2dvals` row prints 0 (a FAILURE) at the pin, at HEAD and after the frozen-layout fixes. A test nobody reads is a guard that cannot fail; the red row inside it is the reason that matters."
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
