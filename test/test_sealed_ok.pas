{ The sealed/abstract class checks must reject the three invalid shapes WITHOUT
  breaking the valid ones: a sealed class WITH a parent (sealing a leaf is the whole
  point of the modifier), and a plain `class abstract` with an abstract method that a
  descendant overrides.

  Guards the false-positive side of test_sealed_class_fail.pas. }
program test_sealed_ok;
{$mode objfpc}
type
  TBase = class
    function Name: AnsiString; virtual;
  end;

  { sealed LEAF: legal, and still dispatches virtually through the base }
  TSealedLeaf = class sealed(TBase)
    function Name: AnsiString; override;
  end;

  { abstract class + abstract method: legal, the descendant supplies the body }
  TAbstractBase = class abstract
    function Kind: AnsiString; virtual; abstract;
  end;

  TConcrete = class(TAbstractBase)
    function Kind: AnsiString; override;
  end;

function TBase.Name: AnsiString; begin Result := 'base'; end;
function TSealedLeaf.Name: AnsiString; begin Result := 'leaf'; end;
function TConcrete.Kind: AnsiString; begin Result := 'concrete'; end;

var
  leaf: TSealedLeaf;
  b: TBase;
  c: TConcrete;
  a: TAbstractBase;
  fails: Integer;

procedure Check(const what, got, want: AnsiString);
begin
  if got = want then writeln('ok   ', what, ' = ', got)
  else
  begin
    writeln('FAIL ', what, ' = ', got, ' (want ', want, ')');
    fails := fails + 1;
  end;
end;

begin
  fails := 0;
  leaf := TSealedLeaf.Create;
  b := leaf;
  Check('sealed leaf, virtual via base', b.Name, 'leaf');

  c := TConcrete.Create;
  a := c;
  Check('abstract base, override via base', a.Kind, 'concrete');

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
