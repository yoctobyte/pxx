

## DECIDED 2026-07-20 — Option 1, stay correctly rounded

**User's call: 1.** crtl's libm keeps correct rounding where glibc is not
correctly rounded. We do not reproduce glibc's errors to make differential
testing quieter.

Correctness over bug-compatibility. It is also a genuinely strong public claim,
and a verifiable one — but **state it with claims discipline**: "judged against
high-precision references", never "matches glibc". The whole point is that we
do NOT match glibc in these cases, and phrasing it as a match would be both
wrong and self-defeating.

Revisit only if a corpus target's oracle diff drowns in libm noise — i.e. if
the cost lands on real differential testing rather than in principle.

## Log
- 2026-07-20 — resolved, commit PENDING.
