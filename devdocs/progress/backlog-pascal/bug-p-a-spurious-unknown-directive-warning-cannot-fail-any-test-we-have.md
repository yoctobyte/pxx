---
track: P
prio: 35
type: bug
blocked-by: []
summary: "The unknown-directive warning (2026-09-04) classifies against a hand-curated list of ~101 names. A name missing from it makes valid code warn — under -Werror, fail — and NO INSTRUMENT WE HAVE CAN SEE THAT: a spurious warning exits 0, so a PASS/FAIL corpus sweep records it as PASS. Two real false positives have already been found and fixed by hand ({$A n}, 153d59777) or filed ({$setc} family, p40). Needs a stderr-counting guard, not a compile sweep."
---

# A spurious unknown-directive warning cannot fail any test we have

`{$SOMETHINGINERT}` warns and then compiles fine, `rc=0`. That is the whole
problem: **the assertion class does not match the defect class.** Every
PASS/FAIL instrument in the repo — the quick tier, a corpus sweep, the
fixedpoint — is blind to it by construction, exactly like the leak case
CLAUDE.md cites, where every output assertion passed while 1504 arrays leaked.

Under `-Werror` it is not cosmetic: valid code stops compiling. That is the
`library` failure of `771b157a6` one level over — a narrowing change rejecting
code someone meant to write.

## What is already known

Censusing fpc 3.2.2's own sources for directive words pxx does not recognise
found two real members, so this is not hypothetical:

- `{$A1}`/`{$A2}`/`{$A4}`/`{$A8}`/`{$A+}`/`{$A-}` — reported as unknown, i.e. as
  a typo, on code fpc accepts. They are `{$PACKRECORDS}` under its Turbo name
  and were also producing the **wrong record layout**. Fixed, `153d59777`.
- The MacPas conditional family — filed separately as
  [[bug-p-macpas-conditional-directives-are-ignored-so-both-arms-compile]] (p40),
  because ignoring a conditional is a different and worse thing than ignoring a
  switch.

## The instrument this wants

Not a compile sweep. One that captures **stderr** across a corpus and counts
`unknown compiler directive` lines with the source path, so a hit on real
`lib/`, `examples/` or non-fixture `test/` code is a candidate false positive —
valid code in this tree should not be warning at all. frankD is building exactly
that against the 2165-source tree; it walks the same list as his PASS/FAIL sweep
and is a different harness. **A zero result needs the planted control**, since a
zero from a probe that never ran reads identically to a real absence.

## Two residuals the guard will still have

1. **It is present-tense over this tree.** The ~101 curated names have a long
   tail that no corpus here reaches — a name absent from this tree but present
   in real FPC code someone compiles tomorrow. The census bounds what is broken
   now, not what the list is missing.
2. **Nothing can see a name LEAVING the inert list.** The existing fixture
   asserts a TOTAL unknown-directive count, which catches a name arriving; a
   name that stops being inert warns somewhere the fixture does not look and the
   total is unchanged. Same "a feature's own tests cannot see what the feature
   took away" shape as `library` — the tests assert the population they planted.

Both residuals are frankD's framing, recorded because they are the part a fix
will be tempted to skip.
