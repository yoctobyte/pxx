unit nilpy_destructor_box;
{ Support unit for test_nilpy_the_last_reference_runs_the_pascal_destructor.npy.
  Every destructor here writes a VISIBLE side effect (a counter the program
  prints), so a row cannot pass by leaking quietly: a destructor that never
  runs, or runs twice, changes the printed number. }
{$MODE PXX}
interface
type
  Counted = class
  public
    tag: Integer;
    constructor Create(t: Integer);
    destructor Destroy; override;
  end;
  Holder = class
  public
    held: Variant;
    constructor Create;
    procedure hold(const v: Variant);
    destructor Destroy; override;
  end;
function destroyed: Integer;
procedure free_it(c: Counted);
procedure make_and_free;
function share_then_free: Variant;
implementation
var gDestroyed: Integer;
function destroyed: Integer; begin destroyed := gDestroyed; end;
constructor Counted.Create(t: Integer); begin tag := t; end;
destructor Counted.Destroy;
begin
  Inc(gDestroyed);
  inherited Destroy;
end;
constructor Holder.Create; begin held := 0; end;
procedure Holder.hold(const v: Variant); begin held := v; end;
destructor Holder.Destroy;
begin
  Inc(gDestroyed, 100);
  held := 0;            { drops the Python reference: re-entrant rc=0 }
  inherited Destroy;
end;
procedure free_it(c: Counted); begin c.Free; end;
procedure make_and_free;
var c: Counted;
begin
  c := Counted.Create(9);
  c.Free;
end;
function share_then_free: Variant;
var c: Counted;
begin
  c := Counted.Create(7);
  share_then_free := c;   { Python now holds a reference too }
  c.Free;                 { ...and Pascal drops its own: Destroy runs HERE }
end;
end.
