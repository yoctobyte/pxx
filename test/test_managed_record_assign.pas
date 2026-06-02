program test_managed_record_assign;

{ Whole-record assignment for records containing managed AnsiString fields.
  The copy is ARC-correct: source fields are retained, the destination's old
  fields released, then the record is bulk-copied. Copy-on-write keeps the
  copies independent, and self-assignment is a no-op. }

{$define PXX_MANAGED_STRING}

type
  TInner = record s: AnsiString; end;
  TRec = record
    a, b: AnsiString;
    inner: TInner;
    n: Integer;
  end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  x, y: TRec;
  i: Integer;

begin
  x.a := 'hello';
  x.b := 'world';
  x.inner.s := 'deep';
  x.n := 5;

  y := x;
  Check(y.a = 'hello');
  Check(y.b = 'world');
  Check(y.inner.s = 'deep');
  Check(y.n = 5);

  { COW: mutating x leaves the earlier copy untouched. }
  x.a := 'changed';
  Check(y.a = 'hello');
  Check(x.a = 'changed');

  { Self-assignment must not corrupt or free the live fields. }
  y := y;
  Check(y.a = 'hello');
  Check(y.b = 'world');

  { Repeated reassignment releases the previous destination each time. }
  for i := 1 to 3 do
    y := x;
  Check(y.a = 'changed');
  Check(y.inner.s = 'deep');
end.
