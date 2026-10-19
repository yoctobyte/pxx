---
track: N
prio: 50
type: bug
---

# test-uforth: filetest.fth raced CPython on a shared file

Found 2026-10-19: `test-uforth: FAIL — 1 of 17 corpora differ`. In filetest,
`FN1 R/O OPEN-FILE` returned a non-zero ior, then THROW -13.

**Cause:** the recipe runs the native uforth and the CPython oracle
concurrently in the same $(UFORTH_SRC) tree, and filetest.fth creates, reopens
and deletes `fatest1.txt` there. Run one after the other, native and CPython
were byte-identical twice. This was not a compiler bug.

**Fix:** filetest.fth alone runs serially (native, then CPython). The other 16
corpora stay in parallel.
