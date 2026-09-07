unit ugxpwrap;
{ THE SPECIALIZING UNIT -- a library wrapping another unit's generic, which is
  the shape this whole fixture exists for. BOTH SECTIONS specialize, because the
  interface and the implementation reach the splice by different paths
  (FlushPendingClassSpecializations anchors one at UnitImplAnchor and streams
  the other at the cursor) and only one of the two would have been covered. }
{$mode objfpc}{$H+}
interface

uses ugxpbase;

type
  TIntBox = specialize TBox<LongInt>;

procedure RunIface;
procedure RunImpl;

implementation

type
  TInt64Box = specialize TBox<Int64>;

procedure RunIface;
var b: TIntBox;
begin
  b := TIntBox.Create;
  b.SetIt(21);
  WriteLn('iface param+result ', b.GetIt);
  WriteLn('iface local        ', b.Twice(21));
  WriteLn('iface self         ', b.ViaSelf);
  WriteLn('iface self named   ', b.SelfHasName);
  WriteLn('iface field        ', b.ViaField);
end;

procedure RunImpl;
var b: TInt64Box;
begin
  b := TInt64Box.Create;
  b.SetIt(1000000);
  WriteLn('impl  param+result ', b.GetIt);
  WriteLn('impl  local        ', b.Twice(1000000));
  WriteLn('impl  self         ', b.ViaSelf);
  WriteLn('impl  self named   ', b.SelfHasName);
  WriteLn('impl  field        ', b.ViaField);
end;

end.
