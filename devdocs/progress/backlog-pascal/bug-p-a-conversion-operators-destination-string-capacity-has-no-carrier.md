---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: frankS
---

# A conversion operator's destination string capacity has no carrier

`class operator Implicit(const a: TTest): TString80` and the same operator
returning `TString90` are refused as duplicates. FPC accepts both declarations.
The destination of a conversion operator is keyed on the return type's KIND, and
every frozen-string kind compares equal (`OpConvResultMatches`, deliberately, so
that `string[N]` resolving to tyString in one position and tyFixedString in
another still matches — toperator93). The declared CAPACITY is what separates
TString80 from TString90, and the proc's RESULT has nowhere to put it.

## The absent carrier, enumerated

The capacity of a `string[N]` is carried once per carrier:

| carrier | declared |
| --- | --- |
| variable | `SymStrCap` |
| type alias | `AliasStrCap` |
| record field | `UFldStrCap` |
| parameter | `ptypesStrCap` (pasparser_proc.inc) |
| **routine RESULT** | **absent** |

Four present, all agreeing, and the fifth never conceived — the exact shape
`ProcRetSetEnumId`'s own comment describes for a different fact ("an ABSENT copy
has no diff, so reading the five against one another could never have produced
it"), and the shape `ptypesStrCap`'s comment describes for the parameter channel
("the FOURTH member of the return-channel family above, and the one that was
missing"). This file has now recorded the same pattern three times.

`ProcRetPtrAlias` is the precedent for the fix's shape: store the alias index
rather than a copy of the pointee's geometry.

**Needs a defs.inc slot** — frankH messaged before it is taken.

## The other half: the use-site ambiguity

Adding the capacity to the key is not sufficient on its own, and the reason is
the interesting part.

`toperator92` and `toperator95` are `%FAIL` rows that PASS today, and they pass
by refusing the wrong thing. FPC accepts their declarations and refuses at the
USE site — toperator92:32 `s := t;` is `Incompatible types: got "TTest" expected
"TString80"`, i.e. ambiguous. pxx refuses at DECLARATION time, toperator92:28,
`duplicate conversion operator`. Same verdict, different reason, and the harness
compares only whether a refusal happened.

So making the key finer must be paired with a use-site ambiguity refusal, or
those two rows flip from passing-for-the-wrong-reason to failing. Four rows move
together: toperator91 and toperator94 (currently skipped, FPC compiles them)
start passing; toperator92 and toperator95 keep passing and start doing it for
FPC's reason.

## A NEGATIVE RESULT, recorded so nobody repeats it

I censused all 212 `%FAIL` rows the harness runs and does not skip, comparing
pxx's first error LINE against fpc's, on the theory that a wrong-reason refusal
shows up as a line mismatch. **It does not, and the census cannot answer this
question.**

- 99 SAME-LINE, 112 DIFF-LINE, 1 auto-gated.
- Of the 112, 110 are within 10 lines of fpc — indistinguishable from ordinary
  position-reporting differences.
- The 2 rows with a gap above 10 lines are `tgeneric105` and `tgenfunc14`, both
  the ALREADY-KNOWN unit-source vacuity, both already auto-gated by the harness.
- **`toperator92`, the row that motivated the census and is a confirmed
  wrong-reason refusal, sits at a 4-line gap — inside the noise band.**

The instrument cannot see the thing it was built for, and it would have reported
112 rows of nothing as a finding. The line is the wrong channel; the DIAGNOSTIC
is the right one, which is what `run_pascal_conformance.sh`'s own DIAGMAP note
already says about the skip-list version of this question ("the diagnostic is
the channel that can observe this class; the exit code cannot"). The same
sentence holds one level over: for a `%FAIL` row the exit code cannot observe a
wrong-reason refusal, and neither can the line number.

Both confirmed instances (toperator92, toperator95) were found by READING the
duplicate-conversion check while working on toperator91, not by the census.
