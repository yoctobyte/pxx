unit ugxpbase;
{ THE TEMPLATE'S UNIT. It deliberately does NOT `uses` the unit that
  specializes it -- that is the ordinary direction for a library, and it is
  exactly the arrangement that made a method unable to see its own arguments:
  the body is re-parsed as THIS unit while its parameters were allocated in the
  other one, so VisibilityAllows(ugxpbase, ugxpwrap) said no.
  bug-p-a-cross-unit-specialized-method-cannot-see-its-own-parameters }
{$mode objfpc}{$H+}
interface

type
  generic TBox<T> = class
  private
    FV: T;
  public
    { every routine-scoped name a method can have, one per method }
    procedure SetIt(a: T);                  { a PARAMETER }
    function  GetIt: T;                     { a RESULT }
    function  Twice(a: T): T;               { both, and a LOCAL }
    function  ViaSelf: T;                   { an explicit SELF }
    function  SelfHasName: Boolean;         { ...and SELF reaching a TObject method }
    function  ViaField: T;                  { a FIELD -- the control that always worked }
  end;

implementation

procedure TBox.SetIt(a: T);
begin
  FV := a;
end;

function TBox.GetIt: T;
begin
  Result := FV;
end;

function TBox.Twice(a: T): T;
var k: T;
begin
  k := a + a;
  Result := k;
end;

function TBox.ViaSelf: T;
begin
  Result := Self.FV;
end;

function TBox.SelfHasName: Boolean;
{ Deliberately a PREDICATE and not the name itself: pxx calls a specialization's
  class `TIntBox` where fpc calls it `TBox<System.LongInt>`, and printing the
  spelling would make this fixture assert one compiler's naming scheme instead
  of the thing it is about. Both agree the name is non-empty, which is all that
  is needed to prove `Self` resolved and dispatched. }
begin
  Result := Self.ClassName <> '';
end;

function TBox.ViaField: T;
begin
  ViaField := FV;
end;

end.
