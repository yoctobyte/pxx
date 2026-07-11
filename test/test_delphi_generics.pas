{ Delphi-style generics surface: TFoo<T> = class decl, TFoo<Concrete> uses,
  procedure TFoo<T>.M impls — desugared to the objfpc template machinery
  (feature-pascal-delphi-generics-syntax). }
program test_delphi_generics;
{$mode delphi}
type
  TBox<T> = class
    Value: T;
    procedure SetIt(v: T);
    function GetIt: T;
  end;

procedure TBox<T>.SetIt(v: T);
begin
  Value := v;
end;

function TBox<T>.GetIt: T;
begin
  Result := Value;
end;

var
  bi: TBox<Integer>;
  bs: TBox<String>;
begin
  bi := TBox<Integer>.Create;
  bi.SetIt(42);
  writeln(bi.GetIt);
  bs := TBox<String>.Create;
  bs.SetIt('hi');
  writeln(bs.GetIt);
end.
