program test_cross_byvalue_aggregate_params;
{ BY-VALUE AGGREGATE PARAMETERS, both directions asserted.

  A by-value row and a `var` row of the same shape sit next to each other on
  purpose. A backend that copies everything passes every by-value row; a
  backend that copies nothing passes every `var` row; only a file containing
  both can tell a correct convention from either failure. The by-value rows say
  MUST NOT CHANGE and the var rows say MUST CHANGE, and each callee prints what
  it sees so a row cannot pass by the callee's write going nowhere at all.

  THE SIZE SPLIT IS THE POINT FOR RECORDS. ir.inc gives a by-value record over
  8 bytes a private temp (it is promoted to by-ref for ABI reasons, so without
  the copy the callee would mutate the caller's storage), and leaves one of 8
  bytes or less to the backend, which pushes its own bytes across one or two
  argument words. wasm32 has no spelling for the second half -- a parameter is
  one typed local and an aggregate is not a wasm value type -- so it takes the
  temp at every size, and TPlain below is exactly the 8-byte case that was
  refused outright before 2026-09-04: `procedure P(r: TPlain)` emitted the
  whole body as `unreachable`.

  Sets are the same question with a different answer per target: x86-64,
  aarch64, arm32 and wasm32 pass a set param's ADDRESS while i386, riscv32 and
  xtensa pass its 32 bytes. Both conventions must produce these same rows,
  which is why the file asserts values and never a layout.

  Compared against the x86-64 build of this same source, so no row carries a
  hand-written answer that could be edited green. }

type
  TPlain = record a, b: Integer; end;                 { 8 bytes: backend's half }
  TWide  = record a, b, c, d, e: Integer; end;        { 20 bytes: ir.inc's half }
  TS     = set of 0..255;

procedure ByValPlain(r: TPlain);
begin
  r.a := 777; r.b := 888;
  writeln('  ByValPlain sees ', r.a, ' ', r.b);
end;

procedure ByValWide(r: TWide);
begin
  r.a := 777; r.e := 999;
  writeln('  ByValWide sees ', r.a, ' ', r.e);
end;

procedure ByValSet(s: TS);
begin
  s := s + [99];
  writeln('  ByValSet sees 99=', 99 in s, ' 1=', 1 in s);
end;

procedure VarPlain(var r: TPlain);
begin
  r.a := 777; r.b := 888;
end;

procedure VarSet(var s: TS);
begin
  s := s + [99];
end;

{ A by-value record and a by-value set among scalars, before and after, so a
  convention that gets the aggregate's slot width wrong corrupts a neighbour
  rather than only itself -- the failure that made the arm32 record ABI bug
  worth a test of its own. }
procedure Mixed(x1: Integer; r: TPlain; x2: Integer; s: TS; x3: Integer);
begin
  r.a := 777; s := s + [99];
  writeln('  Mixed sees ', x1, ' ', r.a, ' ', x2, ' ', 99 in s, ' ', x3);
end;

{ A by-value record read WHOLE rather than field by field: the assignment is a
  record copy out of the parameter's storage, which is a different consumer
  from `r.a`. }
function CopyOut(r: TWide): TWide;
begin
  CopyOut := r;
end;

var
  p: TPlain; w: TWide; s: TS; got: TWide;
begin
  p.a := 1; p.b := 2;
  ByValPlain(p);
  writeln('plain after byval  ', p.a, ' ', p.b, '   (must be 1 2)');

  w.a := 1; w.b := 2; w.c := 3; w.d := 4; w.e := 5;
  ByValWide(w);
  writeln('wide  after byval  ', w.a, ' ', w.e, '   (must be 1 5)');

  s := [1, 2];
  ByValSet(s);
  writeln('set   after byval  99=', 99 in s, ' 1=', 1 in s, '   (must be FALSE TRUE)');

  { The other direction: if these do NOT change, every row above is passing
    because the target copies indiscriminately. }
  VarPlain(p);
  writeln('plain after var    ', p.a, ' ', p.b, '   (must be 777 888)');
  VarSet(s);
  writeln('set   after var    99=', 99 in s, '   (must be TRUE)');

  p.a := 1; p.b := 2;
  s := [1, 2];
  Mixed(10, p, 20, s, 30);
  writeln('mixed after        ', p.a, ' ', 99 in s, '   (must be 1 FALSE)');

  got := CopyOut(w);
  writeln('copyout            ', got.a, ' ', got.c, ' ', got.e, '   (must be 1 3 5)');
  writeln('done');
end.
