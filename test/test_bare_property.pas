program test_bare_property;
{ bug-unqualified-property-in-method: a method may reference its own class's
  properties unqualified (no Self.). Covers field-backed read + write, method-backed
  read, combined read/write, and `not` on a bare boolean property (the value must be
  a canonical Boolean, not a wrong-width load). }

type
  TC = class
  private
    FFlag: Integer;
    FN:    Integer;
    function GetDouble: Integer;
  public
    property Flag: Integer read FFlag write FFlag;   { field-backed r/w }
    property Num:  Integer read FN write FN;         { field-backed r/w }
    property Dbl:  Integer read GetDouble;           { method-backed read }
    procedure Run;
  end;

function TC.GetDouble: Integer;
begin
  Result := FN * 2;              { bare field read inside the getter }
end;

procedure TC.Run;
begin
  Num := 21;                     { bare field-backed write }
  writeln('num=', Num);          { bare read }
  Num := Num + 4;                { bare read + write }
  writeln('num2=', Num);
  writeln('dbl=', Dbl);          { bare method-backed read (FN=25 -> 50) }

  Flag := 0;
  writeln('flagzero=', Flag = 0);
  Flag := 1;
  { `not (Flag = 0)` exercises boolean typing of a bare property read }
  writeln('flagset=', not (Flag = 0));
end;

var
  c: TC;
begin
  c := TC.Create;
  c.Run;
end.
