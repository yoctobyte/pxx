---
slug: bug-p-strict-visibility-is-silent-on-records
track: P
prio: 30
type: bug
status: done
blocked-by: []
owner: ""
summary: "FIXED 2026-09-09. `--strict-visibility` enforced member access control on CLASSES and was silent on RECORDS -- both fields and methods. The ticket's reading was that the vis was RECORDED and the gap was at the access path; the measurement says the REVERSE, and the ticket said to settle that first because one of the two fixes is a no-op. The access path was already wired (EnforceFieldVis at pasparser_lval.inc:3895 and :5891, EnforceMethVis likewise). The STAMP was missing: ParseRecordFields matched `private`/`strict private` as tkIdent+CaseEqual, consumed them and passed a hardcoded VIS_PUBLIC literal to ParseFieldDeclInto, while ParseRecordMethodDecl never wrote UMthVis at all -- and VIS_PUBLIC is 0, so the unstamped default WAS `public` and EnforceMemberVis exited before checking anything. Fix: track the section in ParseRecordFields and stamp it onto fields and methods. Lax default unchanged (EnforceMemberVis still exits on `not StrictVisibility` first), and asserted on the same source in the same Makefile stanza -- configuration was the missing axis, not time."
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

## Log
- 2026-09-09 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.

## 2026-09-09 — fixed, and the ticket's own reading was backwards

The ticket named the fork correctly and picked the wrong side, which is why it
told whoever took it to measure first: *"a stamp fix and a call-site fix are
different changes and one of them is a no-op."* It is the stamp.

**The access path was already wired.** `EnforceFieldVis` is called for records
at `pasparser_lval.inc:3895` and `:5891`, both carrying the comment
`{ --strict-visibility member access control }`.

**The stamp was not.** `ParseRecordFields` recognises the section markers — but
as `tkIdent` + `CaseEqual(CurTok.SVal, 'private')`, NOT as `tkPrivate`, which is
why a token-kind grep finds nothing and reads as "records don't parse
visibility at all". It consumed the marker, `continue`d, and passed a hardcoded
`VIS_PUBLIC` literal to `ParseFieldDeclInto`. `ParseRecordMethodDecl` never
wrote `UMthVis` at all.

**And `VIS_PUBLIC = 0` (`defs.inc:573`), so the unstamped default was
`public`** — `EnforceMemberVis` exits on `if vis = VIS_PUBLIC` before it reads
the context. Every record member was public to the enforcement no matter what
the source said. The expected value collided with the do-nothing value, which
is the CLAUDE.md rule about a probe whose right answer must differ from the
default: had the array defaulted to anything else, this would have been loud.

## What changed

`ParseRecordFields` now tracks `curVis`/`curStrictVis` across the body and
stamps both fields and methods; `ParseRecordMethodDecl` takes the visibility
and writes `UMthVis`.

## Measured, at commit `ae1ce9232` + this change, binary `cd4563b0b667`

| row | default | `--strict-visibility` |
| --- | --- | --- |
| `private` RECORD field, cross-unit | accepts | **rejects** |
| `strict private` RECORD field, cross-unit | accepts | **rejects** |
| `private` RECORD method, cross-unit | accepts | **rejects** |
| public RECORD field / method | accepts | accepts |
| `private` CLASS field (unchanged) | accepts | rejects |
| public CLASS field (unchanged) | accepts | accepts |

**The control that matters is not in that table.** A record method reading its
own `private` AND `strict private` fields, and calling its own private method,
still compiles under the flag — so the fix did not turn enforcement into
blanket rejection. `test_record_visibility.pas` is that control, and it is
drawn from the RECORD population: the class control passed throughout and could
never have caught this.

Diagnostics name the record: `cannot access strict private member "fs" of TR
from here (--strict-visibility)`.

`gate.sh quick` GREEN, read from the log rather than the wrapper's exit code;
FPC seed canary PASS (not SKIP). Self-host fixedpoint `converged after 1
round(s)`.

## Not touched

The lax DEFAULT, which is a stated dialect choice (`defs.inc:3063`), and
`terecs1.pp`'s skip-list entry, which the ticket correctly said this does not
reopen — the conformance runner passes `--strict-case --strict-operator` and
never `--strict-visibility`.
