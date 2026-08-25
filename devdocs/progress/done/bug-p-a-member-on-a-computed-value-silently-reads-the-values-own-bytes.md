---
track: P
prio: 55
type: bug
blocked-by: []
status: done
commit: 582cdc934
summary: "`.member` on a COMPUTED value — a call result, or the result of a type-helper method — built a field read at offset 0 and printed the receiver's own bytes as an Int32. `(F).Twice` printed 113 (ord 'q'); `s.Twice.Twice` and `s.Twice.IsEmpty` both printed 24929 (the two bytes of 'aa'), the trailing member silently dropped. The sibling refusal for a NAMED receiver was narrowed to a declared variable on purpose, and 'not a name' was read as 'leave it alone'."
owner: claude-A
---

# A member on a computed value silently reads the value's own bytes

Found 2026-08-25 while probing `feature-p-delphi-string-helpers` against fpc
3.2.2. Fixed the same session.

## Repro

```pascal
{$mode objfpc}{$H+}{$modeswitch typehelpers}
program one;
type TStrH = type helper for string function Twice: string; end;
function TStrH.Twice: string; begin Result := Self + Self; end;
var s: string;
function F: string; begin Result := 'q'; end;
begin
  s := 'a';
  Writeln(s.Twice.Twice);     { fpc: aaaa    pxx: 24929 }
  Writeln(s.Twice.IsEmpty);   { fpc: FALSE   pxx: 24929 }
  Writeln((F).Twice);         { fpc: qq      pxx: 113   }
end.
```

24929 is `$6161` — `'aa'` read as an Int32. 113 is `ord('q')`. Note the second
row: a DIFFERENT member gives the SAME number, because the trailing selector is
not merely mistyped, it is silently dropped.

## Root cause

`RecFieldType`'s not-found default is "tyInteger at offset 0". Four separate
copies of member dispatch fall through to it:

1. `ParseSelectors` (`pasparser_lval.inc` ~2693)
2. `ParseClassRecordSelectors` (~4065)
3. `PyParseClassRecordSelectors` (NilPy's twin)
4. the grouped-postfix `.` tail in `ParseFactorCore` (`pasparser_expr.inc` ~1116)

Copies 1 and 2 call `RequireRecMember`, which refused an unknown member — but
only when the receiver was a user class (`recId >= REC_UCLASS_BASE`). It said
nothing about `recId = REC_NONE`, i.e. "this is not a record or class at all",
which is exactly what a helper method's return type leaves behind: the selector
loop sets `recId := REC_NONE` for a non-class/record result and then keeps
looping. Copy 4 did not call `RequireRecMember` at all.

The earlier fix for the NAMED case
([[bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes]]) was keyed
on `ASTKind[node] = AN_IDENT` deliberately — a `tk`-keyed version had refused
three working cast-then-deref programs (`PPyVarRec(@v)^.Payload`). That
narrowing was right, but "not a name" was then read as "leave it alone", and
the computed receiver kept the silent behaviour the named one had lost.

## Fix

One arm in `RequireRecMember` (`pasparser_call.inc`) — `recId = REC_NONE` is
refused — plus the missing `RequireRecMember` call in copy 4. Every copy of
member dispatch already asks that function whether the member exists, so
asking it about REC_NONE too is one arm, not a fifth copy.

Deliberately NOT a `tk`-keyed check: `recId` is the thing the fallthrough is
about to index with, so keying the refusal on it cannot disagree with what the
code then does. That is why the three cast-then-deref programs are unaffected
— measured, not assumed: `tools/lib_units_compile.py` says **141 units
compile** on `pinned` and on HEAD alike, and every `examples/**` program that
built before still builds (12 pre-existing failures, byte-identical list).

## What this does NOT fix

Helper methods on a computed receiver stay a gap — FPC chains them fine, and
`(F).Twice`, `'xy'.Twice`, `Copy(s,1,1).Twice`, `s.Twice.Twice` are all now
loud refusals rather than wrong numbers. The constructive half belongs to
[[feature-p-delphi-string-helpers]], whose scope section should grow a line
saying the receiver must be generalised past a declared variable. Verified the
same session: a plain variable receiver (`s.Twice`, `s.IsEmpty`) works,
cross-unit, and matches FPC byte for byte.

## Verification

`test/test_computed_member_fail.pas` and
`test/test_chained_helper_member_fail.pas`, both wired into `test-core` next to
the two `test_scalar_member_*_fail` tests they extend.

`make compiler/pascal26` converged in one round; `tools/gate.sh quick` GREEN;
fpc-testsuite unmoved.
