program test_mgmt_operators_array_field;
{ An ARRAY FIELD of a record whose ELEMENT declares management operators: every
  element is initialized and finalized through the same synthesised loop the
  array-of-record SYMBOL case gets, with an AN_FIELD base instead of an
  AN_IDENT one (AppendManagedFieldOps -> AppendManagedArrayOps).

  THIS FIXTURE IS ITS OWN POSITIVE CONTROL. The defect class here is a declared
  invariant that never runs, and that cannot fail a value check unless the body
  PRINTS the value the operator was supposed to set. Every arm therefore reads
  back `n`, which Initialize is the only writer of; an operator that never runs
  leaves the frame's leftovers there and the row moves.

  Five things it is aimed at, each of which a single zero-based array field in a
  plain record would pass while broken. The .expected IS fpc 3.2.2's output.

  ORDER, TWO RULES THAT ARE NOT THE SAME RULE. Across NESTING levels Initialize
  is post-order and Finalize is pre-order; across ARRAY ELEMENTS both run
  ASCENDING. Baz exercises both at once -- its two elements initialize 2 then 3
  BEFORE its own operator, and on the way out its own runs first and the
  elements still run 2 then 3.

  INDEX SPACE. Baz's field is `array[2..3]`, not `array[0..1]`, because the loop
  runs in SOURCE index space and takes its low bound from the FIELD table
  (UFldArrDimLo), not from the symbol table. A loop hard-coded to 0..n-1 is
  right for every 0-based declaration and silently manages two slots that are
  not the field's for this one.

  DEPTH. Deep reaches the array field through a plain record field, so the walk
  has to descend and then loop rather than only loop at the top level.

  ELEMENTS THAT ARE THEMSELVES NESTED. Wrap's element is TBar, which holds a
  TFoo field -- so inside one element the pre/post-order rule applies again, and
  the loop body is built by the same field walk that built the level above it.

  THE MUTUAL RECURSION. Mix is an array SYMBOL whose element holds an array
  FIELD: symbol loop -> field walk -> field loop. Those two procedures call each
  other, which is why one is forward-declared, and this is the row that would
  fail if only one direction were wired.

  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TPlain = record
    f: array[0..1] of TFoo;
    k: Integer;
  end;
  TBaz = record
    a: array[2..3] of TFoo;
    class operator Initialize(var z: TBaz);
    class operator Finalize(var z: TBaz);
  end;
  TDeep = record
    p: TPlain;
  end;
  TBar = record
    f: TFoo;
    class operator Initialize(var b: TBar);
    class operator Finalize(var b: TBar);
  end;
  TWrap = record
    w: array[0..1] of TBar;
  end;
  TMixElem = record
    m: array[0..1] of TFoo;
  end;

var
  seq: Integer;

class operator TFoo.Initialize(var a: TFoo);
begin
  a.n := seq; writeln('init Foo ', seq); seq := seq + 1;
end;

class operator TFoo.Finalize(var a: TFoo);
begin
  writeln('fin  Foo ', a.n);
end;

class operator TBaz.Initialize(var z: TBaz);
begin
  writeln('init Baz ', seq); seq := seq + 1;
end;

class operator TBaz.Finalize(var z: TBaz);
begin
  writeln('fin  Baz');
end;

class operator TBar.Initialize(var b: TBar);
begin
  writeln('init Bar ', seq); seq := seq + 1;
end;

class operator TBar.Finalize(var b: TBar);
begin
  writeln('fin  Bar');
end;

procedure PPlain;
var b: TPlain;
begin
  b.k := 7;
  writeln('bodyPlain ', b.f[0].n, b.f[1].n, ' ', b.k);
end;

procedure PBaz;
var z: TBaz;
begin
  writeln('bodyBaz ', z.a[2].n, z.a[3].n);
end;

procedure PDeep;
var d: TDeep;
begin
  writeln('bodyDeep ', d.p.f[0].n, d.p.f[1].n);
end;

procedure PWrap;
var w: TWrap;
begin
  writeln('bodyWrap ', w.w[0].f.n, w.w[1].f.n);
end;

procedure PMix;
var arr: array[0..1] of TMixElem;
begin
  writeln('bodyMix ', arr[0].m[0].n, arr[0].m[1].n, arr[1].m[0].n, arr[1].m[1].n);
end;

begin
  seq := 0;
  PPlain;
  PBaz;
  PDeep;
  PWrap;
  PMix;
  writeln('done');
end.
