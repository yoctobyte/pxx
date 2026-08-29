---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A `property` declared inside a `type helper` is not dispatched: `s.Len` where the helper declares `property Len: SizeInt read GetLen` is refused with `a string has no members here`, while `s.GetLen` — the same accessor called directly — works. Properties on a plain record work. This blocks `s.Length`, the headline member of Delphi's TStringHelper, because FPC declares Length as a property over GetLength rather than as a method."
status: done
---

# A type helper's `property` is not dispatched, only its methods are

Found 2026-08-29 by frankB (Track B/P) while probing
[[feature-p-delphi-string-helpers]] before implementing it.

## Measured

One helper, five features, one of them missing:

| declared in a `type helper for string` | pxx |
| --- | --- |
| `function GetLen: SizeInt` — plain method | **works** |
| `function Sub(A: SizeInt): string; overload` + 2-arg sibling | **works**, both arms dispatch |
| `function Sp(const Seps: array of Char): TStringArray` — open-array param | **works** |
| returning a dynamic array | **works** |
| `property Len: SizeInt read GetLen` | **refused** |

```
pascal26:6: error: a string has no members here: pxx does not implement Delphi's
string helpers (s.Length, s.ToUpper, s.Trim, s.Substring) — ...
  near:  WriteLn  Len=  s >>>  Len
```

Delete the `property` line and call `s.GetLen` instead — the identical accessor,
same helper, same receiver — and it compiles and prints 11.

**The same construct works on a plain record.** A record with
`function GetD: Integer;` + `property D: Integer read GetD;` compiles and
`r.D` prints 42. So properties are implemented and helper dispatch is
implemented; what is missing is properties *reached through* helper dispatch.

That is the double-case shape from
`devdocs/dev/normalise-dont-special-case.md` — one construct, two paths to it,
the second one missing — and it is the second instance on this feature: the
receiver-generalisation gap recorded in `feature-p-delphi-string-helpers`
(literal, call-result and chained receivers) is the same defect on a different
axis of the same dispatch block.

## Why it matters more than one member

FPC declares `Length` on `TStringHelper` as a **property**:

```pascal
Function GetLength : SizeInt;
property Length : SizeInt read GetLength;
```

`s.Length` is the single most-used member of that surface, it is the example in
pxx's own refusal diagnostic, and it is the first thing a Delphi-2009+-style
program hits. Every other member in the ticket's scope — `ToUpper`, `ToLower`,
`Trim`, `Substring`, `IndexOf`, `StartsWith`, `Contains`, `Replace`, `Split`,
`IsEmpty`, `PadLeft`, `PadRight` — is a plain function and works today. So the
library side can deliver the whole surface **except** the one member everybody
reaches for first.

Spelling `Length` as a method instead would compile and would be wrong: it
diverges from the reference for no reason other than working around this, which
is the compiler-appeasement workaround CLAUDE.md rules out for every track. The
platonic declaration is a property.

## Where to look

`pasparser_lval.inc`, the TYPE-HELPER dispatch block — the same block the
receiver-generalisation gap names. That the two gaps sit in one block is the
argument for fixing them together rather than twice.

**Unverified.** I did not read that block; the pointer comes from
`feature-p-delphi-string-helpers`'s own measured-state section, which located
the receiver dispatch there. Treat it as a lead.

## Gate

`make compiler/pascal26` + a positive test where a helper's property is read
through a variable receiver, with the `.expected` produced by fpc under
`{$modeswitch typehelpers}`. Keep the record-property case in the same test as
the control, since it is the arm that already works and is what stops the fix
being written as a special case.

## Fixed 2026-08-29 (frankB) — the guard was too narrow, not the machinery

Three lines, and none of them a property path.

```pascal
mci := FindHelperForType(Syms[idx].TypeKind, Syms[idx].RecName);
if (mci >= 0) and ((FindUMeth(mci, GetTokenStr(TokPos)) >= 0) or
                   (FindUProp(mci, GetTokenStr(TokPos)) >= 0)) then
```

`pasparser_lval.inc`, the TYPE-HELPER dispatch block. The block already hands
the receiver to `ParseClassRecordSelectors` with the helper as the record id,
and that is the same machinery advanced records use — **it has resolved
properties all along**. The guard asked `FindUMeth` and nothing else, so a
property-named member failed the test and fell through to
`a string has no members here`. The property arm was never missing; it was
never reached. Widening the guard is therefore `normalise-dont-special-case` in
its cheapest form: no second path was added, one was stopped being excluded.

**Measured after:** `s.Length` on an `AnsiString` prints 5 where fpc 3.2.2
prints 5, through sysutils' real `TStringHelper` — a consumer that already
existed, because [[feature-p-delphi-string-helpers]] declared it the FPC way and
left it platonic rather than respelling it as a method. The library needed no
edit at all when the compiler caught up, which is the no-appeasement rule
paying out rather than merely being observed.

### Gate

`make compiler/pascal26` → converged after 1 round, `56b95ec7a505`.
`test/test_type_helper_property.pas` + `.expected` wired into `test-core`,
carrying **both arms**: the helper property (the fix) and a record property (the
control that always worked). The control is the point — the defect was the
intersection of two working features, so a test of only the broken arm would let
the fix be rewritten as a helper special case. Verified negative: the test
compiles and passes on the new binary and fails on the pinned one with
`a value of this type has no members`.

Checked for over-widening rather than assumed: `test_scalar_member_fail.pas` and
`test_scalar_member_int_fail.pas` are both still correctly refused, and the
record-property control still answers 42.

### Two things found on the way, neither filed as new

**`private` is not enforced.** `s.GetLength` compiles here and is
`Illegal qualifier` in FPC, because FPC declares that accessor private.
Attributed before assuming: it compiles on the **pinned** binary too, so it
predates this fix, and `private` is not enforced on a plain record either — it
is general, not helper-specific. Already parked as
`rainy-day/idea-visibility-enforcement`, so it is noted here rather than
re-filed. By CLAUDE.md's table it is *we accept a form FPC rejects* → not a
defect.

**The sibling gap this ticket was paired with is already gone.** See the
string-helpers ticket: all six receiver forms work today, verified on the
pinned binary, so the fix was not mine and the recorded table was stale.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
