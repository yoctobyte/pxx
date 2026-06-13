program test_cross_managed_aggregate_locals;

{ Cross-target managed-aggregate *local* oracle (compile with
  -dPXX_MANAGED_STRING). A local whose managed extent exceeds a pointer — a
  record with a managed field, or a variant — must have its full frame slot
  zero-initialised so first use sees nil, and its body ARC ops must run. Output
  is identical on every target as on x86-64. }

type
  TRec = record
    name: AnsiString;
    n: Integer;
  end;

procedure UseRecord;
var
  r: TRec;
begin
  r.name := 'hello';
  r.n := 42;
  writeln(r.name, ' ', r.n);
  r.name := r.name + ' world';   { managed field reassignment }
  writeln(r.name);
end;

procedure UseVariant;
var
  v: Variant;
begin
  v := 7;
  writeln(v);
  v := 'text';
  writeln(v);
  v := 3.5;
  writeln(v);
end;

procedure NestedReuse(k: Integer);
var
  r: TRec;
begin
  r.name := 'k';
  r.n := k;
  writeln(r.name, r.n);
end;

var
  i: Integer;
begin
  UseRecord;
  UseVariant;
  for i := 1 to 3 do
    NestedReuse(i);
end.
