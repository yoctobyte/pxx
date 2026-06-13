program test_cross_byref_params;

{ Cross-target by-ref parameter ABI oracle: same output on every target as on
  x86-64. Exercises the pointer-sized-handle param convention that the i386
  prologue previously rejected:
    - const Variant param (passed by reference to the 16-byte value)
    - const record param  (by-ref aggregate)
    - var record param    (by-ref, mutates through the pointer)
  Variant/record locals are not yet supported on cross targets, so the
  variant lives in a global and records are passed from the main body. }

type
  TPoint = record
    x, y: Integer;
  end;

var
  gv: Variant;
  p, q: TPoint;

procedure VShow(const v: Variant);
begin
  writeln(v);
end;

function PSum(const r: TPoint): Integer;
begin
  PSum := r.x + r.y;
end;

procedure PBump(var r: TPoint; d: Integer);
begin
  r.x := r.x + d;
  r.y := r.y + d;
end;

begin
  gv := 42;
  VShow(gv);
  gv := 'hi';
  VShow(gv);

  p.x := 3;
  p.y := 4;
  writeln(PSum(p));

  q := p;
  PBump(q, 10);
  writeln(q.x);
  writeln(q.y);
  writeln(PSum(q));
end.
