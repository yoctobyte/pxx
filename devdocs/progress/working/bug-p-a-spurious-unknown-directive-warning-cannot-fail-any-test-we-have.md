---
track: P
prio: 35
type: bug
blocked-by: []
summary: "PRIO CONFIRMED AT 35 BY THE 2026-09-05 CENSUS AUDIT -- its demand line is not a corpus (valid code stops compiling under -Werror), unlike its sibling, which was parked. The unknown-directive warning (2026-09-04) classifies against a hand-curated list of ~101 names. A name missing from it makes valid code warn — under -Werror, fail — and NO INSTRUMENT WE HAVE CAN SEE THAT: a spurious warning exits 0, so a PASS/FAIL corpus sweep records it as PASS. Two real false positives have already been found and fixed by hand ({$A n}, 153d59777) or filed ({$setc} family, p40). Needs a stderr-counting guard, not a compile sweep. A SECOND AXIS is recorded here and HAS NOW BEEN SWEPT (2026-09-05): a KNOWN directive carrying an unrecognised VALUE is invisible to this warning, which keys on the directive NAME. Censusing fpc 3.2.2's own sources for directive VALUES rather than names returned two real members on the first pass -- {$ALIGN ON}/{$ALIGN OFF} and {$ASMMODE gas}/{$STANDARD} -- both fixed. THE VALUE AXIS IS CLOSED FOR THE NAMES THIS COMPILER DISPATCHES ON. THE NAME AXIS HAS NOW BEEN SWEPT TOO (2026-09-05, frankA), against the population the tree census structurally cannot see: fpc 3.2.2's OWN 9197 sources rather than ours, every candidate RUN through both compilers, and the verdict keyed on whether fpc recognises the NAME (`Illegal compiler directive` = fpc does not know it either = our warning is right) rather than on exit code. SEVEN false positives found and fixed -- asmcpu copyright hugecode hugepointerarithmeticnormalization hugepointercomparisonnormalization minstacksize screenname -- all names fpc knows and deliberately ignores on this target, so valid FPC code warned and under -Werror failed. Guarded by the fixture's TOTAL row, which emits 13 on the pre-change compiler and 6 after. STILL OPEN: residual 2 (nothing can see a name LEAVING the inert list), and residual 1 narrowed rather than closed -- a name used only by Delphi, a vendor unit or FPC 3.3+ is still invisible."
status: working
owner: frankA
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

## The value axis, swept 2026-09-05 — and what made it a separate axis

The name census and the value census are **not the same instrument narrowed**:
this warning fires on `command`, so for the ~46 names the dispatch knows, ANY
value reaches an arm and whatever that arm does is final. `{$ALIGN POWER}` and
`{$ALIGN ON}` were indistinguishable to every sweep in the tree.

Method: walk `/usr/share/fpcsrc` (9197 sources, 129 distinct directive names)
for `{$NAME ARG}`, group the ARGs by NAME, keep the names pxx dispatches on,
then compile one probe per (name, value) under **both** compilers and compare
the verdicts. Two members, both real code fpc accepts:

- **`{$ALIGN ON}` / `{$ALIGN OFF}`** (5 uses) — `align` and `packrecords` share
  one arm, so `align` inherited `packrecords`' value space. They are one
  SETTING with two VALUE SPACES: fpc refuses `{$PACKRECORDS ON}` with *Illegal
  record alignment specifier*, so widening both would have been wrong in the
  other direction. Measured `{$ALIGN ON}` = `{$A+}` = 4 and `{$ALIGN OFF}` =
  `{$A-}` = 1, not the default 8.
- **`{$ASMMODE gas}` (17 uses) and `{$ASMMODE standard}`** — and the arm's
  error message asserted a census that was wrong in BOTH directions: it named
  `direct` as part of "the FPC set" and fpc 3.2.2 refuses it. Sweeping 16
  candidate values gives fpc's actual set as `intel default att gas standard`.
  Which syntax each selects was measured by assembling `movl $42, %eax` and
  `mov eax, 42` under each rather than inferred from the name.

Both fixed, with `test_directive_value_space_matches_fpc.pas` asserting
RELATIONS between spellings so it carries no per-target width. Pin v403 refuses
all three constructs.

What the sweep does NOT cover, and why the name axis above is still open: it
can only ask about names the dispatch already has. A directive fpc knows and
pxx does not still reaches the terminal arm and warns, and that warning is
still invisible to every PASS/FAIL instrument here.

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

## The NAME axis, swept 2026-09-05 (frankA) — residual 1 is closed against fpc's own sources

Residual 1 said the present-tense census "bounds what is broken now, not what
the list is missing", because a name absent from THIS tree but present in real
FPC code is structurally invisible to a harness that walks our sources. That is
the half frankD's clean 2166-source run could not speak to, and it is now swept.

**Population: fpc 3.2.2's own sources**, 9197 files under
`/usr/share/fpcsrc/3.2.2` (compiler, rtl, packages) — deliberately not this
tree, because this tree is the population that was already clean. 130 distinct
directive words appear there.

**Method: run them, do not read them.** Every candidate was compiled by BOTH
compilers rather than diffed against the curated list, so an error in reading
our own list cannot produce a finding or hide one.

**The discriminator is what fpc says about the NAME, not whether it compiles.**
fpc answering `Illegal compiler directive "$X"` means fpc does not know the name
either and our warning is CORRECT. fpc answering anything else — a note, a
target-specific warning, or an error about the VALUE — means fpc knows the name
and ours was a false positive. This mattered: a bare probe makes a
value-requiring directive error under fpc, and on exit code alone `$ASMCPU`
reads identically to a name fpc rejects. **Positive control:** an invented name
warns under both compilers.

**Seven false positives, each with fpc's own words:**

| directive | fpc 3.2.2 says | uses in fpc's sources |
| --- | --- | --- |
| `asmcpu` | `Error: Illegal assembler CPU instruction set specified ""` | 3 |
| `copyright` | `Warning: Copyright only supported for target netware` | 1 |
| `hugecode` | `Note: Ignored compiler switch "HUGECODE"` | 1 |
| `hugepointerarithmeticnormalization` | `Warning: Directive … ignored for the current target platform` | 1 |
| `hugepointercomparisonnormalization` | same | 1 |
| `minstacksize` | `Warning: MINSTACKSIZE is not supported by the target OS` | 1 |
| `screenname` | `Warning: Screenname only supported for target netware` | 2 |

All seven are class 0 under the existing membership rule, and `asmcpu` is the
one worth stating: it RESTRICTS the assembler's instruction set, so ignoring it
is strictly more permissive — the same reading that already puts `$X-` on the
list. `minstacksize` is the sibling of `maxstacksize`, which was listed;
grep-for-the-sibling would have found it years earlier than a census did.

**The fix is guarded, and the guard fails on the old compiler.** All seven join
the silent block of `test_pascal_directive_unknown_warns.pas`, whose TOTAL
assertion is the only row that can catch an inert directive starting to warn.
Measured: the pre-change compiler `e6af001d6c0e3bf2` emits 13 warnings on that
fixture and the post-change one emits 6.

**What this does NOT close.** The sweep is bounded by fpc 3.2.2's own sources; a
name used only by Delphi, by a vendor unit, or by FPC 3.3+ is still invisible,
so residual 1 is narrowed to "outside FPC's own tree", not eliminated. Residual
2 (nothing can see a name LEAVING the inert list) is untouched by this and
remains the open half — though the fixture's re-populated class-1 block now
makes the adjacent version of that failure visible, which is how this sweep
found `test-core` red.

## RESIDUAL 2 IS CLOSED, 2026-09-05 (frankD)

*"Nothing can see a name LEAVING the inert list."* It can now.

**The gap, measured before building anything:** `PAS_INERT_DIRECTIVES` holds
**107** names; `test_pascal_directive_unknown_warns.pas` mentions **26** of
them. So **81 were unguarded** — a name that stopped being inert would warn in
a file nobody compiles, and that fixture's TOTAL row, which is the thing
protecting the arriving direction, would not move by one.

**`test_pascal_directive_inert_list_is_complete.pas`** writes out all 107 and
asserts **zero** warnings.

**Three rows, and each closes a different way for it to be vacuous:**

| row | what it stops |
| --- | --- |
| `.silent` — 0 warnings | the actual defect: a name leaves the list |
| `.run` — the program prints `ok` | a comparison whose input never existed. A file that fails to compile also emits no `warning:` line |
| `.population` — 107 directives still in the source | **deleting the rows to silence a failure.** An empty fixture prints zero warnings AND `ok` |

The third row is the one worth arguing for: **a zero census is meaningless
until the probe is proven live**, and until it is proven to still contain
anything. Both of those are run-time assertions here rather than sentences in a
comment.

**Positive control, run rather than reasoned:** removing `zerobasedstrings`,
`y` and `apptype` from `PAS_INERT_DIRECTIVES` and rebuilding makes the fixture
emit exactly **three** warnings, each naming its own directive. That also rules
out the failure mode this design was most exposed to — a name whose bare
spelling is swallowed by an earlier arm and never reaches the classifier, which
would have sat in the fixture contributing nothing while looking guarded.

**The file is HAND-MAINTAINED and must stay so.** Generating it from
`PAS_INERT_DIRECTIVES` at test time would make it agree with the list by
construction — a guard that cannot fail, which is precisely this ticket's
subject. The instruction in its header is: when you deliberately remove a name,
delete its line in the same commit, and the diff becomes the record of what
stopped being inert.

**Residual 1 is untouched and remains the whole of what is left** — a name used
only by Delphi, a vendor unit or FPC 3.3+ is still invisible, because no corpus
here contains it. That one is bounded by frankA's sweep against fpc's own 9197
sources and cannot be closed by a fixture.
