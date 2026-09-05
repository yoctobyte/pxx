---
track: P
prio: 35
type: bug
blocked-by: []
summary: "FIXED, and the instrument is committed as `tools/directive_name_sweep.py`. A spurious `unknown compiler directive` exits 0, so every PASS/FAIL harness here scores it as PASS, and under -Werror it stops valid code compiling. Both axes are now swept and both residuals answered. VALUE axis (a known name with an unrecognised value, invisible to a name census): closed for the names this compiler dispatches on -- $ALIGN ON/OFF and $ASMMODE gas/standard fixed. NAME axis, swept three times, each population finding what its predecessor structurally could not see: this tree (2166 sources) clean; fpc 3.2.2's own compiler/rtl/packages, SEVEN false positives; FPC's TESTSUITE plus rtl-generics via library_candidates/ (2501 sources, 9 names that appear nowhere in fpcsrc), TWO more -- checklowaddrloads and targetswitch, both accepted silently by fpc. Residual 2 (nothing can see a name LEAVING the inert list) closed by frankD's 109-name fixture with a population row. Residual 1 is narrowed to Delphi-only, vendor and FPC 3.3+ sources, for which no corpus exists on this box -- the sweep tool takes a corpus directory and asserts its own control, so that run is one command whenever such a corpus arrives."
status: done
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

## THE NAME AXIS, THIRD RUN — the corpus the second run could not see, 2026-09-05 (frankA)

The fpcsrc sweep above stated its own residual: *"a name used only by Delphi, by
a vendor unit, or by FPC 3.3+ is still invisible."* One member of that set was
**already on this box and was not Delphi at all**: `/usr/share/fpcsrc/3.2.2`
holds `compiler`, `rtl` and `packages` and **not `tests`**, and a testsuite is
precisely the corpus that exists to spell edge cases. `library_candidates/` has
it — 2304 testsuite sources, plus `rtl-generics` (Delphi-flavoured) and
`fpc-rtl`.

90 distinct directive names there. **Nine appear nowhere in fpcsrc**, so nothing
had ever asked about them: `bitpacking checklowaddrloads mmx output_format
saturation targetswitch unitpath z z1`. Same instrument, same discriminator
(what fpc says about the NAME, never the exit code), same asserted positive
control.

**Two false positives, both from those nine:**

| directive | fpc 3.2.2 | real use |
| --- | --- | --- |
| `checklowaddrloads` | accepts silently; a bare probe errors on the VALUE, which is recognition | `tests/test/texception10.pp:4`, `{$CHECKLOWADDRLOADS+}` |
| `targetswitch` | accepts silently, value and all | `tests/test/jvm/tlowercaseproc.pp:6`, `{$targetswitch lowercaseprocstart}` |

Both class 0, and **both by the sibling reading rather than a fresh argument**:
`CHECKLOWADDRLOADS` is `CHECKPOINTER`'s sibling — a target-specific runtime
check whose absence is strictly more permissive — and `TARGETSWITCH` is
`MODESWITCH`'s, a knob for target behaviours pxx has no targets for. Each
sibling was already on the list. That is **twice now** that grep-for-the-sibling
would have beaten a census to the finding (`minstacksize`/`maxstacksize` was the
first).

Guarded in both fixtures, and the population row moves 107 → 109. The two real
sources still do not compile, for reasons that have nothing to do with this —
`texception10.pp` hits an `expected ':=' before ';'` and `tlowercaseproc.pp` is
a standalone unit — and saying so is the point: **the directive warning is the
part that was wrong, and it is the part that is fixed.**

## The instrument is committed: `tools/directive_name_sweep.py`

Rebuilt from this ticket's description twice now, which is one time too many.
It takes corpus directories (or `--only <name>`), runs every candidate through
both compilers, and keys the verdict on fpc's message rather than its exit code.

**Both control paths are asserted, not described.**

- *Detection:* two invented names must warn under BOTH compilers, checked
  FIRST, and the run **aborts** rather than reporting clean if they do not — a
  probe that never reaches the classifier reads exactly like a corpus with
  nothing wrong in it.
- *Reporting:* `PXX=` points it at another compiler. Against
  `stable_linux_amd64/default/pinned`, which predates today's fix, it reports
  `checklowaddrloads` and `targetswitch` and **not** `checkpointer` — so the
  finding path is known to fire, and known to discriminate.

## Resolved (2026-09-05, frankA)

Everything this ticket asked for exists: the stderr-counting guard (frankD,
2166 sources, clean, with the four fixtures as its live control), the value-axis
sweep, three name-axis sweeps over three populations, the 109-name completeness
fixture that closes residual 2, and now the instrument itself.

**Residual 1 is not closed and cannot be closed here** — no Delphi-only, vendor
or FPC 3.3+ corpus exists on this box. What changed is that it is no longer a
standing piece of work: it is one command against a directory that does not yet
exist. Resolving rather than parking, because a ticket whose only remaining step
is "wait for a corpus" is a ticket nobody can pick up.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
