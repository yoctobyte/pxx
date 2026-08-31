program TestEmitObjNoExport;
{ POSITIVE CONTROL for the x86-64 object writer's "defines nothing linkable"
  refusal. A guard that cannot fail is not a guard, and it prints PASS -- so
  the refusal needs a case it MUST reject, asserted, and this is it: a program
  with a body, data, bss and an external, and not one C-convention definition
  anywhere. Nothing here could be linked against, so emitting an object would
  hand someone a file whose failure surfaces at their link step.

  It must stay export-free. If a `cdecl` routine is ever added here the row in
  test-emit-obj goes green for the opposite reason and stops testing anything.
  feature-a-a-general-x86-64-relocatable-object-writer }

procedure ext_notify(v: Integer); external;

var
  g: Integer;

function AddUp(n: Integer): Integer;
var k, acc: Integer;
begin
  acc := 0;
  for k := 1 to n do acc := acc + k;
  Result := acc;
end;

begin
  g := AddUp(9);
  ext_notify(g);
  write('done');
end.
