program test_a_records_static_class_method_is_reachable_through_an_instance;
{ A record's `class function ... static` has TWO spellings at the call site --
  through the TYPE NAME and through an INSTANCE -- and only the first one
  worked. The instance arm built Self from __pxxRttiOf(receiver), which is the
  right answer for a class and reads a record's own first bytes as an object
  header: `R.T1(4)` SEGFAULTED where `TR.T1(4)` on the line above printed 4.
  terecs3.pp is the corpus row (`F.Test1(4)`).
  Rows 1-2 are the pair; 3-6 carry the other receiver shapes that reach the
  same arm; 7-8 are the CLASS control, which must keep the runtime-class Self. }
{$mode delphi}
type
  TR = record
  public
    const C: Integer = 1;
    var F3: Integer;
    class var CV: Integer;
    class function Bare: Integer; static;
    class function Add(n: Integer): Integer; static;
    class procedure SetCV(const v: Integer); static;
    class property P: Integer read CV write SetCV;
    function Inst(n: Integer): Integer;
  end;

  TBase = class
    class function Who: Integer; virtual;
  end;
  TDeriv = class(TBase)
    class function Who: Integer; override;
  end;

class function TR.Bare: Integer;
begin
  Result := 11;
end;

class function TR.Add(n: Integer): Integer;
begin
  Result := C + n;
end;

class procedure TR.SetCV(const v: Integer);
begin
  CV := v * 2;
end;

function TR.Inst(n: Integer): Integer;
begin
  Result := F3 + n;
end;

class function TBase.Who: Integer;
begin
  Result := 100;
end;

class function TDeriv.Who: Integer;
begin
  Result := 200;
end;

var
  R: TR;
  A: array[0..1] of TR;
  B: TBase;
begin
  R.F3 := 5;
  WriteLn('1 ', TR.Add(4));        { through the TYPE NAME -- always worked }
  WriteLn('2 ', R.Add(4));         { through an INSTANCE -- the segfault }
  WriteLn('3 ', R.Bare);           { no argument list at all }
  WriteLn('4 ', R.Inst(4));        { the non-static sibling, same receiver }
  A[1].F3 := 9;
  WriteLn('5 ', A[1].Add(4));      { a receiver that is not a bare name }
  with R do
    WriteLn('6 ', Add(4));         { unqualified, inside `with` }
  R.P := 3;
  WriteLn('7 ', R.P, ' ', TR.CV);  { class property, static setter, via instance }
  B := TDeriv.Create;
  WriteLn('8 ', B.Who);            { CLASS control: Self is the RUNTIME class }
  B.Free;
  B := TBase.Create;
  WriteLn('9 ', B.Who);
  B.Free;
end.
