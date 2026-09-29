program test_free_on_a_tobject_in_a_unit_runs_the_destructor;
{ Inside a UNIT, `TObject(p).Free` and `o.Free` on a TObject ran FreeMem
  alone -- the override's destructor never ran (fpc runs it). The third line
  is the program-file control, which always worked. Expected output is
  fpc 3.2.2's.
  bug-a-free-on-a-tobject-in-a-unit-skips-the-overridden-destructor }
{$mode objfpc}
uses tobject_free_unit;
var
  Destroyed: Integer = 0;
type
  TThing = class
    destructor Destroy; override;
  end;
destructor TThing.Destroy;
begin
  Inc(Destroyed);
  inherited Destroy;
end;
begin
  FreeObj(Pointer(TThing.Create));
  writeln('unit TObject(p).Free: ', Destroyed);
  FreeTObj(TThing.Create);
  writeln('unit o.Free (o: TObject): ', Destroyed);
  TObject(Pointer(TThing.Create)).Free;
  writeln('program TObject(p).Free: ', Destroyed);
end.
