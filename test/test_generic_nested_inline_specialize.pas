program test_generic_nested_inline_specialize;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
uses SysUtils;

type
  generic TBox<T> = class
    V: T;
  end;
  generic TPair<TK, TV> = record
    Key: TK;
    Val: TV;
    class function Make(const a: TK; const b: TV): specialize TPair<TK, TV>; static;
  end;
  generic TList<T> = class
  private
    FA: array of T;
  public
    procedure Add(const v: T);
    function Get(i: Integer): T;
    function Count: Integer;
  end;

  { a nested inline specialize as a record FIELD }
  TRec = record
    F: specialize TBox<specialize TBox<Integer>>;
  end;

var
  { ...as a VAR type, both same-template and CROSS-template nesting }
  bb: specialize TBox<specialize TBox<Integer>>;
  lp: specialize TList<specialize TPair<Integer, AnsiString>>;
  b1: specialize TBox<Integer>;
  r:  TRec;
  pr: specialize TPair<Integer, AnsiString>;

class function TPair.Make(const a: TK; const b: TV): specialize TPair<TK, TV>;
begin Result.Key := a; Result.Val := b; end;
procedure TList.Add(const v: T);
begin SetLength(FA, Length(FA) + 1); FA[High(FA)] := v; end;
function TList.Get(i: Integer): T; begin Result := FA[i]; end;
function TList.Count: Integer; begin Result := Length(FA); end;

{ ...as a PARAMETER }
procedure ShowNested(x: specialize TBox<specialize TBox<Integer>>);
begin WriteLn('param: ', x.V.V); end;

{ ...as a function RESULT }
function MakeNested(n: Integer): specialize TBox<specialize TBox<Integer>>;
begin
  Result := specialize TBox<specialize TBox<Integer>>.Create;
  Result.V := specialize TBox<Integer>.Create;
  Result.V.V := n;
end;

{ ...as a LOCAL }
procedure LocalNested;
var z: specialize TBox<specialize TBox<Integer>>;
begin
  z := MakeNested(9);
  WriteLn('local: ', z.V.V);
end;

begin
  b1 := specialize TBox<Integer>.Create; b1.V := 7;
  bb := specialize TBox<specialize TBox<Integer>>.Create;
  bb.V := b1;
  WriteLn('var:   ', bb.V.V);

  r.F := MakeNested(4);
  WriteLn('field: ', r.F.V.V);

  ShowNested(bb);
  WriteLn('result:', MakeNested(5).V.V);
  LocalNested;

  { cross-template: the outer template was parsed BEFORE the inner one existed }
  pr := specialize TPair<Integer, AnsiString>.Make(3, 'three');
  lp := specialize TList<specialize TPair<Integer, AnsiString>>.Create;
  lp.Add(pr);
  WriteLn('cross: ', lp.Get(0).Key, '/', lp.Get(0).Val, ' n=', lp.Count);
end.
