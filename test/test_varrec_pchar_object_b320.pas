{ array-of-const TVarRec tags for PChar and OBJECT elements (b320).

  `PChar(S)` in an `array of const` literal was boxed as vtPointer (5) — FPC boxes
  it as vtPChar (6), and consumers dispatch on the tag: fpjson's
  `TJSONArray.Create(['x', PChar(S)])` raised "Cannot add non-nil pointer" instead
  of adding a string element. A class INSTANCE element fell through to vtInteger
  (0), truncating the pointer on read. Verified against FPC: vtInteger=0 vtChar=2
  vtPChar=6 vtObject=7 vtAnsiString=11. }
program test_varrec_pchar_object_b320;
{$mode objfpc}{$h+}

type
  TThing = class
  public
    Tag: Integer;
  end;

procedure Probe(const A: array of const);
var
  I: Integer;
begin
  for I := 0 to High(A) do
  begin
    Write('  [', I, '] vtype=', A[I].VType);
    case A[I].VType of
      0:  Writeln(' int=', A[I].VInteger);
      6:  Writeln(' pchar-first=', PChar(A[I].VPChar)^);
      7:  Writeln(' obj.tag=', TThing(A[I].VObject).Tag);
      11: Writeln(' str=', AnsiString(A[I].VAnsiString));
    else
      Writeln;
    end;
  end;
end;

const
  S = 'A string';
var
  T: TThing;
begin
  T := TThing.Create;
  T.Tag := 77;
  Probe([42, PChar(S), T, 'managed']);
end.
