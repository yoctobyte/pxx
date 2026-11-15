---
slug: bug-c-a-redeclared-array-is-never-baked-into-data
track: C
prio: 50
type: bug
status: done
created: 2026-11-15
found-by: claude-opus (toybox size)
tags: [cfront, static-data]
blocked-by: []
summary: "Under --c-static-data an array declared extern first (the header shape: `extern char *tzname[2];` then `char *tzname[2] = {...};`) was excluded from CPlaceGlobalInData by `declSymIsNew or not wasArr`, so it kept its .bss slot and its stores ran in the init thunk. The exclusion guarded a real hazard: CGrowGlobalArray moved a grown array to a new slot without carrying SymAllocSize, so a placement would have copied the old size. That is fixed (and with it the object symbol's st_size for a grown array), and the exclusion is gone. CGlobalOffsetIsReferenced still keeps an array that code already references in .bss."
---

# A redeclared array was never baked

Found because crtl's tzname kept the whole literal pool alive in every toybox
object. Test: test/c_redeclared_array_bakes.c.
