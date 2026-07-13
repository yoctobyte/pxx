{ An untyped BOOLEAN constant keeps its type (b326).

  `const S = True;` went through ConstEval, which collapses to an integer, so S
  was registered tyInteger — and `array of const` boxed it as vtInteger:
  fpjson's TJSONArray.Create([S]) built a NUMBER element where FPC builds a
  BOOLEAN. Bare True/False consts now register tyBoolean (a folded boolean
  EXPRESSION still lands in the integer path). Verified against FPC. }
program test_bool_const_varrec_b326;
{$mode objfpc}{$h+}

const
  ST = True;
  SF = False;
  N  = 3;

procedure Probe(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do
  begin
    Write('vt=', A[I].VType);
    if A[I].VType = 1 then Writeln(' b=', A[I].VBoolean)
    else Writeln(' i=', A[I].VInteger);
  end;
end;

function Pick(B: Boolean): String; begin Result := 'bool'; end;
function Pick(I: Integer): String; begin Result := 'int'; end;

begin
  Probe([ST, SF, N, True]);
  Writeln('pick=', Pick(ST));   { overloads see the boolean type too }
end.
