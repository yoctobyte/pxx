---
track: P
prio: 35
type: bug
blocked-by: []
summary: "PRIO CONFIRMED AT 35 BY THE 2026-09-05 CENSUS AUDIT -- its demand line is not a corpus (valid code stops compiling under -Werror), unlike its sibling, which was parked. The unknown-directive warning (2026-09-04) classifies against a hand-curated list of ~101 names. A name missing from it makes valid code warn — under -Werror, fail — and NO INSTRUMENT WE HAVE CAN SEE THAT: a spurious warning exits 0, so a PASS/FAIL corpus sweep records it as PASS. Two real false positives have already been found and fixed by hand ({$A n}, 153d59777) or filed ({$setc} family, p40). Needs a stderr-counting guard, not a compile sweep. A SECOND AXIS is now recorded here too: a KNOWN directive carrying an unrecognised VALUE is invisible to this warning, which keys on the directive name -- `{$MODE TOTALNONSENSE}` was silent until 2026-09-05."
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

## The present-tense census came back CLEAN, 2026-09-04 (frankD)

The stderr-counting harness described above was built and run twice over 2166
sources — once before this session's `{$A n}` and `{$setc}` work, once after —
and both arms give the identical four hits:

    test_pascal_directive_unknown_in_include.pas:27  {$bogusinmain}
    test_pascal_directive_unknown_in_include.pas:4   {$bogusinsideinclude}
    test_pascal_directive_unknown_warns.pas:27       {$PACKRECRDS}
    test_pascal_directive_unknown_warns.pas:28       {$definitelynotadirective}

**Zero in `lib/`, zero in `examples/`, zero in any non-fixture source.** So the
inert list has no present-tense false positive in this tree, and the fixes here
introduced none.

**The four ARE the live control** — real compiles through the same harness,
firing on the population the instrument exists to fire on, so the zero is a
measured absence rather than a probe that never ran. No planted extra was
needed; the existing fixtures already were one.

Scope, stated exactly: the run was at `0ee4a97b8`, which does **not** contain
`bc0ed4164`. That commit added only Makefile assertions over generated printf
fixtures — no directive name, no classifier change — so it cannot move this
result, but the census did not observe it.

**Residual 1 above is now the whole of what is left, and is unchanged.** A clean
tree census says nothing about the ~101-name list's long tail. `{$A n}` is the
proof: absent from this entire tree, silently producing a different record
layout, and no census over `lib/` could ever have reached it. That is what the
fpc-corpus source census is for, and it is a third instrument with the opposite
blind spot to both the compile sweep and this one.

## Census audit, 2026-09-05 (frankA) — this ticket KEEPS its prio; its sibling did not

Owner asked for the sweep's tickets to be re-checked, because a ticket sourced
from a corpus census inherits that corpus's priorities rather than ours. The
sweep produced exactly two tickets and they come out differently:

* [[bug-p-macpas-conditional-directives-are-ignored-so-both-arms-compile]] **had
  the defect** and is now in `rainy-day/`. Its 31549 `{$setc}` occurrences are
  FPC's macOS bindings — precise, correct, and a count of text we do not intend
  to compile ([[decide-which-pascal-dialects-pxx-targets]]).
* **This one does not.** Its demand line is not a corpus at all: valid code stops
  compiling under `-Werror`. That claim survives whatever FPC's tree happens to
  contain, so 35 stands. The census is where it was FOUND, not what ranks it —
  which is the distinction the audit was looking for.

## A new instance of residual 1, created deliberately and bounded by measurement

`{$MODE}` now REJECTS an unrecognised value (`decide-which-pascal-dialects-pxx-targets`;
before this, the whole handler was `DelphiMode := CaseEqual(name, 'delphi')`, so
every other value — `{$MODE MACPAS}`, `{$MODE ISO}`, `{$MODE TOTALNONSENSE}` —
compiled silently). **That is exactly the narrowing this ticket exists to warn
about, one directive further on**, and it is worse than a spurious warning
because it is a hard error rather than something `-Werror` has to promote.

It is bounded the way this ticket's residual 1 says a curated list cannot
normally be bounded — **by asking the reference compiler instead of recalling
its list.** Measured against fpc 3.2.2 on 2026-09-05: FPC has exactly eight
modes (`fpc objfpc tp delphi delphiunicode macpas iso extendedpascal`) and
rejects everything else, `-Mturbo` included. So the accepted set is not a
curated prefix of an open-ended space with a long tail — it is FPC's whole set
minus the three dialects we do not implement, plus `pxx`. There is no tail for a
name to hide in.

The check earned its keep immediately: a draft of the accept list carried
`turbo` as an alias for `tp`, which is invented — FPC rejects it in both
spellings (`-Mturbo` is `Illegal parameter`, `{$mode turbo}` is `Illegal
compiler switch "TURBO"`). Recalling the list would have shipped a name that
does not exist; asking fpc removed it before the commit.

Note for whoever builds the stderr guard: `{$MODE X}` is a **known directive
with an unrecognised value**, so it never appeared in the unknown-directive
census at all — that instrument keys on the directive NAME. Measured
2026-09-05: `{$TOTALLYUNKNOWNDIRECTIVE}` warns and `{$MODE TOTALNONSENSE}` was
completely silent. A value-space hole is a second axis the name-space census
cannot see, and `{$MODE}` will not be the only directive with one.
