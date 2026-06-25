program test_generic_class_in_program;
{ bug-generic-class-methods-in-program: a generic class whose method bodies are
  implemented in a PROGRAM (not a unit) used to fail ("expected name") because the
  2-pass declaration prescan buffered the template method twice. The buffered
  method is now recorded once and streamed by specialize. }
type
  generic TBox<T> = class
    Value: T;
    procedure SetIt(v: T);
    function GetIt: T;
  end;

procedure TBox.SetIt(v: T); begin Self.Value := v; end;
function TBox.GetIt: T; begin GetIt := Self.Value; end;

type
  TIntBox = specialize TBox<Integer>;
  TStrBox = specialize TBox<string>;

var
  bi: TIntBox;
  bs: TStrBox;
begin
  bi := TIntBox.Create;
  bi.SetIt(7);
  writeln(bi.GetIt);            { 7 }
  bs := TStrBox.Create;
  bs.SetIt('hi');
  writeln(bs.GetIt);           { hi }
end.
