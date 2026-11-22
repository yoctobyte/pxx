---
slug: bug-c-increment-of-a-bool-is-not-converted-to-0-or-1
track: C
prio: 40
type: bug
status: done
created: 2026-11-22
found-by: claude-pxx (fixing bug-crtl-stdbool-defines-bool-as-int)
tags: [cfront, bool]
blocked-by: []
summary: "DONE 2026-11-22: `_Bool b = 1; b++` read back 2, and `b--` from 0 gave 255: AN_INCDEC added to the byte. C99 6.5.2.4 makes b++ `b += 1` converted to _Bool, so ++ always leaves 1 and -- flips the value. CMakeIncDec now lowers a _Bool operand through an assignment, with the postfix value rebuilt from the old one. Test c_stdbool26 (the incdec line)."
---

# An increment of a _Bool is not converted to 0 or 1

See bug-crtl-stdbool-defines-bool-as-int for the context and the test.
