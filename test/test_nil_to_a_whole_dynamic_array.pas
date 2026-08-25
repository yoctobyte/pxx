program test_nil_to_a_whole_dynamic_array;
{ `a := nil` on a WHOLE dynamic array means EMPTY THE ARRAY, whatever the
  element type is.

  It reached the record-shaped `:= nil` arms instead, because an array symbol's
  TypeKind IS its element kind and ResolveNodeRec answers with the ELEMENT rec.
  Both arms zeroed RecSize bytes at the array's DATA pointer, so:
    - handle non-nil -> the first element is overwritten and Length never
      changes. FPC says 0; pxx said 2. Silent, exit 0.
    - handle nil (an already-empty array, or an `out` parameter, which
      ClearManagedOutParam clears by emitting exactly `d := nil`) -> the
      zero-fill runs at address 0. SIGSEGV.

  One exclusion had already been written for the sibling arm on this same `if`
  chain (bug-a-assigning-a-dynamic-array-of-interfaces-is-lowered-as-an-
  interface-assign) and the other two arms did not get it — the miss
  normalise-dont-special-case ends on.

  Three element categories, because the three arms disagreed about which of them
  they caught: a COM interface, a plain record, and a method pointer (a 16-byte
  {Code,Data} record, the shape `OnClick := nil` uses).

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  ITest = interface
    procedure Nop;
  end;
  TTest = class(TInterfacedObject, ITest)
    procedure Nop;
  end;
  TRec  = record a, b: LongInt; end;
  TEvt  = procedure of object;

  TIA = array of ITest;
  TRA = array of TRec;
  TEA = array of TEvt;
  TSA = array of AnsiString;
  TLA = array of LongInt;

procedure TTest.Nop; begin end;

{ `out` of each: the compiler clears a managed out param by emitting `d := nil`,
  which is the nil-handle face of the same bug — it faulted before the body ran. }
procedure FillIntf(n: LongInt; out arr: TIA);
var i: LongInt;
begin
  SetLength(arr, n);
  for i := 0 to n - 1 do arr[i] := TTest.Create;
end;

procedure FillRec(n: LongInt; out arr: TRA);
var i: LongInt;
begin
  SetLength(arr, n);
  for i := 0 to n - 1 do arr[i].a := i;
end;

procedure ClearIntf(var arr: TIA); begin arr := nil; end;
procedure ClearRec(var arr: TRA);  begin arr := nil; end;

var
  ia: TIA; ra: TRA; ea: TEA; sa: TSA; la: TLA;
  i: LongInt;
begin
  { nil onto an ALREADY-NIL handle: this is the one that faulted }
  ia := nil; ra := nil; ea := nil; sa := nil; la := nil;
  WriteLn('empty  : ', Length(ia), Length(ra), Length(ea), Length(sa), Length(la));

  { nil onto a populated handle: this is the one that silently did nothing }
  SetLength(ia, 2); ia[0] := TTest.Create;
  SetLength(ra, 2); ra[0].a := 7;
  SetLength(ea, 2);
  SetLength(sa, 2); sa[0] := 'x';
  SetLength(la, 2); la[0] := 9;
  WriteLn('filled : ', Length(ia), Length(ra), Length(ea), Length(sa), Length(la));
  ia := nil; ra := nil; ea := nil; sa := nil; la := nil;
  WriteLn('cleared: ', Length(ia), Length(ra), Length(ea), Length(sa), Length(la));

  { through a var parameter — the store must reach the CALLER's variable }
  SetLength(ia, 3); SetLength(ra, 3);
  ClearIntf(ia); ClearRec(ra);
  WriteLn('varparm: ', Length(ia), Length(ra));

  { through an out parameter — cleared on entry by the compiler, then filled }
  FillIntf(4, ia); FillRec(5, ra);
  WriteLn('outparm: ', Length(ia), Length(ra));
  for i := 0 to Length(ra) - 1 do Write(ra[i].a);
  WriteLn;

  { and again onto the now-populated ones, to prove the release path runs twice }
  FillIntf(2, ia); FillRec(2, ra);
  WriteLn('reout  : ', Length(ia), Length(ra));

  ia := nil; ra := nil;
  WriteLn('done   : ', Length(ia), Length(ra));
end.
