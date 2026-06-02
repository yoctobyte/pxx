{$define PXX_MANAGED_STRING}
program test_dynarray_ansistring;

var
  a: array of AnsiString;
  b: array of AnsiString;

procedure Check(ok: Boolean);
begin
  if ok then
    writeln(1)
  else
    writeln(0);
end;

procedure TestLocal;
var
  local: array of AnsiString;
begin
  SetLength(local, 2);
  local[0] := 'local';
  local[1] := local[0] + ' array';
  Check(local[0] = 'local');
  Check(local[1] = 'local array');
end;

begin
  Check(Length(a) = 0);
  SetLength(a, 3);
  a[0] := 'one';
  a[1] := 'two';
  a[2] := 'three';
  Check(a[0] = 'one');
  Check(a[2] = 'three');

  { Indexed writes clone shared array storage and preserve element refs. }
  b := a;
  b[0] := 'ONE';
  Check(a[0] = 'one');
  Check(b[0] = 'ONE');
  Check(b[1] = 'two');

  { Resize retains copied strings and zero-initializes new managed slots. }
  SetLength(b, 5);
  Check(Length(b) = 5);
  Check(b[0] = 'ONE');
  Check(b[1] = 'two');
  Check(b[4] = '');
  b[3] := b[1] + ' plus';
  Check(b[3] = 'two plus');

  SetLength(b, 1);
  Check(Length(b) = 1);
  Check(b[0] = 'ONE');
  Check(a[2] = 'three');

  SetLength(b, 0);
  Check(Length(b) = 0);
  Check(a[1] = 'two');
  TestLocal;
  SetLength(a, 0);
  Check(Length(a) = 0);
end.
