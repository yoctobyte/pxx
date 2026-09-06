---
slug: bug-p-strict-visibility-is-silent-on-records
track: P
prio: 30
type: bug
status: backlog
blocked-by: []
owner: ""
summary: "`--strict-visibility` enforces member access control on CLASSES and is silent on RECORDS -- both fields and methods. Measured 2026-09-06, four shapes x two compilers: a cross-unit read of a `private` CLASS field and of a `strict private` one are REJECTED under the flag (`cannot access private member \"fy\" of TC from here`), while a `private` RECORD field and a `private` RECORD method COMPILE under the same flag. Identical at the pin and at HEAD, so this is old, not a regression. fpc 3.2.2 rejects all three field rows with `identifier idents no member`. The lax DEFAULT is deliberate and is not the subject here -- the defect is that the opt-in parity flag silently covers only half the shapes it names, so a program that turns it on gets a clean bill for accesses it never checked."
---

# `--strict-visibility` covers classes and not records, and says nothing about the difference

Not a compat question. Us accepting what fpc rejects is not a defect (CLAUDE.md) and the
lax default is a stated dialect choice (`defs.inc:3063`: *"PXX's dialect parses the markers
but grants access from anywhere -- the deliberate lax ergonomics"*). **The defect is in the
flag**: `--strict-visibility` is documented as *"enforce private/protected across units"*
(`compiler.pas:880`) and enforces it for two of the four shapes it accepts markers on.

**A guard that cannot fail on records is not a guard on records**, and nothing in the
output distinguishes "checked and fine" from "not checked" -- the same clean-bill-written-
by-nobody shape as an exemption list that cannot tell the two apart.

## Measured

Two units, one program per row; `vu1.pas` declares `TR = record private fx` plus
`TC = class private fy strict private fz`, and each program reads one of them cross-unit.

| shape | default | `--strict-visibility` | pin | fpc 3.2.2 |
| --- | --- | --- | --- | --- |
| `private` CLASS field | accepts | **rejects** `cannot access private member "fy" of TC from here (--strict-visibility)` | same | `identifier idents no member "fy"` |
| `strict private` CLASS field | accepts | **rejects** `cannot access strict private member "fz" of TC` | same | `identifier idents no member "fz"` |
| `private` RECORD field | accepts | **accepts** | same | `identifier idents no member "fx"` |
| `private` RECORD method | accepts | **accepts** | same | (not probed) |

Controls, both branched on: a PUBLIC class field still compiles under the flag (the flag is
not rejecting everything), and the flag flips two of four rows (the flag is on). The pin
column is not decoration -- the finding this came out of was correctly controlled against
the pin, and **the pin agrees on every row in both flag states**, so no pin control could
have surfaced this. The missing axis was CONFIGURATION, not time.

fpc rows need `{$modeswitch advancedrecords}` for the record to parse at all; that is the
oracle's requirement, not ours.

## Where to look

`EnforceMemberVis` (`pasparser_class.inc:58`) implements the full scoping rule and is
correct on the rows that reach it. `EnforceFieldVis` (`:86`) and `EnforceMethVis` (`:99`)
are the aimed wrappers, called from `pasparser_lval.inc:3843` and `:5767` (plus the two
mirrored sites in `pyparser.inc`). Records DO get a `UCls` entry (`UClsIsRecord[ci]`) and
the class-body loop stamps `curVis` for them (`pasparser_decl.inc:7444-7459`), so the vis is
almost certainly RECORDED and the gap is at the access path -- **but that is the reading,
not the measurement.** Whoever takes this should establish which of the two it is before
fixing either; a stamp fix and a call-site fix are different changes and one of them is a
no-op. `--strict-visibility` is also reachable as `{$STRICT_VISIBILITY ON}`.

## Disposition of the row that surfaced it

None. `terecs1.pp` is skip-listed `gap: accepts-invalid` at `0fe46e061` and that stays
correct: it is a RECORD row, the runner passes only `--strict-case --strict-operator`, and
the default is lax by design. This ticket does not reopen it.
