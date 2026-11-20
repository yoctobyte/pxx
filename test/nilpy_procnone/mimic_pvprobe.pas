unit mimic_pvprobe;
{ Pascal PROCEDURES called from NilPy, as a value and as a statement.
  bug-n-a-procedure-shim-in-value-position-yields-a-number-not-none }
{$MODE PXX}
interface
uses pylib;
procedure poke(x: Integer);
function pokes: Integer;
type
  K = class
  public
    hits: Integer;
    procedure touch;
  end;
implementation
var total: Integer;
procedure poke(x: Integer); begin total := total + x; end;
function pokes: Integer; begin Result := total; end;
procedure K.touch; begin hits := hits + 1; end;
end.
