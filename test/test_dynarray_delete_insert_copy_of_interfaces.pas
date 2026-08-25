program test_dynarray_delete_insert_copy_of_interfaces;
{ Delete / Insert / Copy over an `array of IFoo` must retain the elements that
  end up in the fresh buffer.

  They did not. The three lowerings (AN_DYN_COPY, AN_DYN_DELETE, AN_DYN_INSERT)
  each carried their own copy of "which element types need a retain walk", and
  all three named exactly AnsiString and managed-record — so a COM-interface
  element got none. The old buffer's element-aware release DOES know kind 4, so
  `Delete(a, 2, 2)` over five interface elements destroyed all five and left the
  three survivors pointing at freed memory: a use-after-free from ordinary code
  (fpc-testsuite tarray11).

  ManagedElemKind exists precisely to be the one answer to that question — its
  own comment records that the policy had been written out NINE times and every
  copy was missing kind 4. These were the tenth, eleventh and twelfth.

  The destructor logs, so the .expected asserts WHICH objects die and WHEN.

  KNOWN DIVERGENCE, deliberately kept out of the asserted region: pxx destroys
  the survivors at SCOPE EXIT where FPC destroys them at the `a := nil`, because
  the fresh-buffer temp holds a reference until then —
  bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit. Every line
  below is inside one procedure whose exit is the last event, so the ORDER the
  two compilers print is identical; do not add a statement after the final nil
  without re-checking that.

  .expected IS fpc 3.2.2's own output on this source. }
{$mode objfpc}
type
  ITest = interface
    function Value: LongInt;
  end;

  TTest = class(TInterfacedObject, ITest)
    v: LongInt;
    constructor Create(x: LongInt);
    destructor Destroy; override;
    function Value: LongInt;
  end;

  TIA = array of ITest;

constructor TTest.Create(x: LongInt); begin v := x; end;
destructor TTest.Destroy; begin WriteLn('  destroy ', v); inherited; end;
function TTest.Value: LongInt; begin Result := v; end;

procedure Fill(var a: TIA; n, base: LongInt);
var i: LongInt;
begin
  SetLength(a, n);
  for i := 0 to n - 1 do a[i] := TTest.Create(base + i);
end;

procedure Show(const tag: string; const a: TIA);
var i: LongInt;
begin
  Write(tag);
  for i := 0 to Length(a) - 1 do Write(' ', a[i].Value);
  WriteLn;
end;

procedure DeleteCase;
var a: TIA;
begin
  WriteLn('delete:');
  Fill(a, 5, 0);
  Delete(a, 2, 2);
  Show('  kept:', a);          { survivors must still be ALIVE and readable }
  a := nil;
end;

procedure DeleteHeadCase;
var a: TIA;
begin
  WriteLn('delete-head:');
  Fill(a, 4, 10);
  Delete(a, 0, 2);
  Show('  kept:', a);
  a := nil;
end;

procedure CopyCase;
var a, b: TIA;
begin
  WriteLn('copy:');
  Fill(a, 4, 20);
  b := Copy(a, 1, 2);
  Show('  src :', a);
  Show('  cpy :', b);
  a := nil;
  Show('  cpy :', b);          { the copy must survive the source }
  b := nil;
end;

procedure ShrinkCase;
var a: TIA;
begin
  WriteLn('shrink:');
  Fill(a, 3, 30);
  SetLength(a, 1);
  Show('  kept:', a);
  a := nil;
end;

begin
  DeleteCase;
  DeleteHeadCase;
  CopyCase;
  ShrinkCase;
  WriteLn('end');
end.
