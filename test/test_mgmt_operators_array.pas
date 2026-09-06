program test_mgmt_operators_array;
{ An ARRAY of a record with management operators: every element is initialized
  and finalized, through a loop this pass synthesises (AppendManagedArrayOps).

  Two things the fixture is aimed at, both of which a 0-based single-element
  test would pass while broken:

  ORDER. Elements go ASCENDING in BOTH directions -- fpc does not reverse an
  array on the way out. Measured against 3.2.2, whose output this .expected IS.
  The forward rule for siblings and the pre/post-order rule across NESTING
  levels are different rules, and Q exercises both at once: within one element
  the field's Initialize precedes the containing record's, and the elements
  themselves still run 0 then 1.

  INDEX SPACE. P's array is `array[3..5]`, not `array[0..2]`, because the loop
  runs in SOURCE index space -- the AN_INDEX node it builds is read exactly the
  way `a[3]` is written. A loop hard-coded to 0..n-1 is right for every 0-based
  declaration and silently initializes three slots that are not the array's for
  this one.

  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TBar = record
    f: TFoo;
    k: Integer;
    class operator Initialize(var a: TBar);
    class operator Finalize(var a: TBar);
  end;

var
  seq: Integer;

class operator TFoo.Initialize(var a: TFoo);
begin
  a.n := seq;
  writeln('init Foo ', seq);
  seq := seq + 1;
end;

class operator TFoo.Finalize(var a: TFoo);
begin
  writeln('fin  Foo ', a.n);
end;

class operator TBar.Initialize(var a: TBar);
begin
  a.k := seq;
  writeln('init Bar ', seq);
  seq := seq + 1;
end;

class operator TBar.Finalize(var a: TBar);
begin
  writeln('fin  Bar ', a.k);
end;

procedure P;
var arr: array[3..5] of TFoo;
begin
  writeln('body ', arr[3].n, arr[4].n, arr[5].n);
end;

procedure Q;
var b: array[0..1] of TBar;
begin
  writeln('bodyQ ', b[0].f.n, b[1].f.n, b[0].k, b[1].k);
end;

begin
  seq := 0;
  P;
  Q;
  writeln('done');
end.
