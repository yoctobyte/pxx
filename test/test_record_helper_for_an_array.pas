program test_record_helper_for_an_array;
{$mode delphi}{$H+}{$modeswitch typehelpers}
{ A `record helper for` whose target is an ARRAY type. Until 2026-09-09 Self
  typed as Integer inside the body and the call site refused the member
  outright, because there is no tyArray in TTypeKind: a helper target was
  representable as a scalar kind or a record id and an array is NEITHER, so
  ParseTypeKind answered its unknown-name default and every consumer read Self
  as whatever that default was.

  The STRING helper rows are the in-file control that says type helpers work at
  all, exactly as the ticket's repro carried one -- without them a total failure
  of the helper machinery would look like this bug.
  bug-p-self-in-a-record-helper-for-a-dynamic-array-types-as-integer }
type
  TArr = array of LongInt;
  TFix = array[0..3] of LongInt;
  TStr = AnsiString;

  TArrHelper = record helper for TArr
    function Cnt: LongInt;
    procedure Fill(v: LongInt);          { Self BY REFERENCE: the write must stick }
    function Sum: LongInt;
  end;
  TFixHelper = record helper for TFix
    function Cnt: LongInt;
  end;
  TStrHelper = record helper for TStr
    function Cnt: LongInt;
  end;

function TArrHelper.Cnt: LongInt;
begin
  Result := Length(Self);
end;

procedure TArrHelper.Fill(v: LongInt);
var i: LongInt;
begin
  for i := 0 to High(Self) do Self[i] := v;
end;

function TArrHelper.Sum: LongInt;
var i: LongInt;
begin
  Result := 0;
  for i := 0 to High(Self) do Result := Result + Self[i];
end;

function TFixHelper.Cnt: LongInt;
begin
  Result := Length(Self);
end;

function TStrHelper.Cnt: LongInt;
begin
  Result := Length(Self);
end;

var a: TArr; f: TFix; s: TStr;
begin
  SetLength(a, 3);
  s := 'abcd';
  WriteLn('dyn=', a.Cnt);        { 3 — the ticket's headline row }
  WriteLn('fixed=', f.Cnt);      { 4 — NOT in the ticket; fails identically without the fix }
  WriteLn('str=', s.Cnt);        { 4 — the control that says helpers work }
  a.Fill(5);
  WriteLn('sum=', a.Sum);        { 15 — Self is by reference, so Fill's writes survive }
end.
