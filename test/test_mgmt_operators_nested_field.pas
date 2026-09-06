program test_mgmt_operators_nested_field;
{ A record that CONTAINS a managed record now gets its field's Initialize and
  Finalize, at any depth. The desugar walks the field table and builds a field
  path per call; before this it refused outright.

  THE ORDER IS THE POINT OF THIS FILE AND IT IS NOT UNIFORM. Measured against
  fpc 3.2.2, not assumed:

    Initialize is POST-order  -- the fields, then the record's own operator.
    Finalize   is PRE-order   -- the record's own operator, then the fields.
    Within one level it is declaration order FORWARD for BOTH directions.

  The two halves look contradictory beside each other and are both real: it is
  construct/destruct symmetry ACROSS nesting levels, and no reversal at all
  among siblings. A test asserting only "init and fin both ran" passes with the
  order inverted, which is why every row here prints a distinguishable number.
  feature-pascal-management-operators-nested-and-array }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    v: LongInt;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TInner = record p: TFoo; q: TFoo; end;
  TBar = record
    a: TFoo;
    n: TInner;
    b: TFoo;
  end;
  TOwn = record
    f: TFoo;
    class operator Initialize(var a: TOwn);
    class operator Finalize(var a: TOwn);
  end;
var seq: LongInt;

class operator TFoo.Initialize(var a: TFoo);
begin a.v := seq; Inc(seq); WriteLn('init Foo ', a.v); end;
class operator TFoo.Finalize(var a: TFoo);
begin WriteLn('fin  Foo ', a.v); end;
class operator TOwn.Initialize(var a: TOwn);
begin WriteLn('init Own'); end;
class operator TOwn.Finalize(var a: TOwn);
begin WriteLn('fin  Own'); end;

{ four managed fields at two depths: a, n.p, n.q, b }
procedure Nested;
var b: TBar;
begin
  WriteLn('body ', b.a.v, b.n.p.v, b.n.q.v, b.b.v);
end;

{ the record has its OWN operator AND a managed field }
procedure OwnAndField;
var o: TOwn;
begin
  WriteLn('body ', o.f.v);
end;

begin
  seq := 0;
  Nested;
  OwnAndField;
  WriteLn('done');
end.
