program test_mgmt_operators_class_field_nested;
{ A management-operator record NESTED inside a class field's record, and an
  operator record that also holds operator records. fpc 3.2.2 runs a record
  inside a CLASS pre-order for BOTH operators -- the outer Initialize before
  its fields' (so TWrap.Initialize sees k=0), the outer Finalize before its
  fields' -- unlike the post-order Initialize a LOCAL record gets. pxx
  flattens the nesting into descriptor members in that order. The class is
  built and freed through an ANCESTOR-typed variable on purpose. .expected is
  fpc 3.2.2's output byte for byte. feature-pascal-management-operators-on-a-class-field }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TWrap = record
    a: TFoo;
    k: Integer;
    b: TFoo;
    class operator Initialize(var x: TWrap);
    class operator Finalize(var x: TWrap);
  end;
  TPlainWrap = record
    p: TFoo;
  end;
  TBase = class
    w: TWrap;
    destructor Destroy; override;
  end;
  TCls = class(TBase)
    pw: TPlainWrap;
    z: TFoo;
  end;
var cnt: Integer = 0;
class operator TFoo.Initialize(var a: TFoo);
begin Inc(cnt); a.n := cnt; WriteLn('  Foo.Init ', a.n); end;
class operator TFoo.Finalize(var a: TFoo);
begin WriteLn('  Foo.Fin ', a.n); end;
class operator TWrap.Initialize(var x: TWrap);
begin x.k := x.a.n * 100 + x.b.n; WriteLn('  Wrap.Init k=', x.k); end;
class operator TWrap.Finalize(var x: TWrap);
begin WriteLn('  Wrap.Fin k=', x.k); end;
destructor TBase.Destroy;
begin WriteLn('  Destroy'); inherited; end;
var b: TBase;
begin
  WriteLn('create');
  b := TCls.Create;
  WriteLn('w.k=', b.w.k, ' z=', TCls(b).z.n);
  WriteLn('free');
  b.Free;
  WriteLn('end');
end.
