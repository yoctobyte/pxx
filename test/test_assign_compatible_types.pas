program test_assign_compatible_types;
{ The other half of test_assign_incompatible_types_fail: everything the
  incompatibility check must NOT start refusing. A whitelist check is only as
  good as the list of things it lets through, and the dialect deliberately
  allows conversions FPC does not — so this is the specification of what stays
  legal, and it RUNS rather than merely compiling, because "accepted" and
  "correct" are different claims.
  bug-p-an-assignment-is-not-type-checked-at-all }
{$mode objfpc}{$H+}
type TE = (eA, eB);
     TB = class x: Integer; end;
     TD = class(TB) y: Integer; end;
var s: AnsiString; ss: ShortString; ch: Char; wc: WideChar; u: UCS4Char;
    i: Integer; by: Byte; i64: Int64; d: Double; sg: Single;
    p: Pointer; pc: PChar; v: Variant; b: TB; dd: TD; e: TE; st: set of TE;
    arr: array[0..3] of Byte; dyn: array of Integer;
begin
  { a character is a legal SOURCE for a string, in every encoding }
  ch := 'q'; s := ch; ss := ch;
  wc := WideChar(65); s := wc;
  { NOT `s := u` -- UCS4Char is LongWord in disguise, FPC refuses it, and pinned
    pxx accepted it and segfaulted. It belongs in the FAIL half of this pair. }
  u := UCS4Char(66); i := Integer(u);
  { the string family converts among itself }
  s := 'abc'; ss := s; s := ss;
  { every numeric widening and narrowing }
  by := 7; i := by; i64 := i; i := Integer(i64); d := i; sg := d; d := sg;
  { pointers take a class, and a class takes its descendant }
  dd := TD.Create; b := dd; p := b; pc := PChar(s); p := pc; p := nil;
  { Variant assigns to and from everything by design }
  v := i; i := v; v := s; s := v; v := d; d := v; v := ch; ch := v;
  { aggregates assign to their own kind }
  e := eA; st := [eA, eB]; arr[0] := by; SetLength(dyn, 2); dyn[0] := i;
  WriteLn('compat ', i, ' ', s, ' ', by, ' ', Ord(e), ' ', Length(dyn));
  dd.Free;
end.
