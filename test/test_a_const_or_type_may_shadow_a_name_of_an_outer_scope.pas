{ The negative control for
  test_a_const_or_type_may_not_redeclare_a_var_declared_before_it: a const or
  type in an INNER scope (a routine, a class body) may reuse an outer name; a
  forward class declaration states its name twice; and a program may redeclare
  System's consts (MaxSmallInt, MaxInt) in any spelling -- fpc's own
  tests/test/cg/tcase2.pp does. fpc accepts all of these. }
program test_a_const_or_type_may_shadow_a_name_of_an_outer_scope;
{$mode objfpc}
const
  maxsmallint = 100;
  MaxInt = 200;
var
  outer: Integer;
  shade: Integer;

procedure ConstInside;
const outer = 'inner const';
begin
  writeln(outer);
end;

procedure TypeInside;
type shade = Integer;
var s: shade;
begin
  s := 7;
  writeln('type inside ', s);
end;

type
  TFwd = class;
  TFwd = class
  public
    type outer = Integer;
    function Get: outer;
  end;

function TFwd.Get: outer;
begin
  Result := 9;
end;

var f: TFwd;
begin
  outer := 1; shade := 2;
  ConstInside;
  TypeInside;
  f := TFwd.Create;
  writeln(outer, ' ', shade, ' ', f.Get, ' ', maxsmallint, ' ', MaxInt);
  f.Free;
end.
