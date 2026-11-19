program test_mgmt_operators_class_field_array;
{ ...and a FIXED ARRAY of such records as a class field: every element is
  initialised at construction and finalised at Free, in index order. This is
  where pxx and fpc 3.2.2 DIFFER, deliberately: fpc 3.2.2 finalises the
  elements but never initialises them (they print 0 here under fpc). pxx
  treats the array as it already treats a fixed array of such records in a
  RECORD field or a local -- each element gets both operators -- because a
  Finalize of a value Initialize never set is the inconsistent half. The
  .expected is pxx's; it equals fpc's on every line that does not involve
  the array. feature-pascal-management-operators-on-a-class-field }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TFoo = record
    v: Integer;
    class operator Initialize(var a: TFoo);
    class operator Finalize(var a: TFoo);
  end;
  TBar = record
    s: AnsiString;
    w: Integer;
    class operator Initialize(var a: TBar);
    class operator Finalize(var a: TBar);
  end;
  TCls = class
    tag: Integer;
    f: TFoo;
    arr: array[0..1] of TFoo;
    constructor Create(t: Integer);
    destructor Destroy; override;
  end;
  TDer = class(TCls)
    g: TBar;
  end;
  TCC = class of TCls;
  TPlain = class
    x: Integer;
  end;

var cnt: Integer = 0;

class operator TFoo.Initialize(var a: TFoo);
begin Inc(cnt); a.v := cnt; WriteLn('  TFoo.Initialize -> v=', a.v); end;
class operator TFoo.Finalize(var a: TFoo);
begin WriteLn('  TFoo.Finalize v=', a.v); end;
class operator TBar.Initialize(var a: TBar);
begin a.w := 77; a.s := 'bar'; WriteLn('  TBar.Initialize'); end;
class operator TBar.Finalize(var a: TBar);
begin WriteLn('  TBar.Finalize w=', a.w, ' s=', a.s); end;

constructor TCls.Create(t: Integer);
begin tag := t; WriteLn('  TCls.Create tag=', tag, ' f.v=', f.v, ' arr=', arr[0].v, ',', arr[1].v); end;
destructor TCls.Destroy;
begin WriteLn('  TCls.Destroy tag=', tag); inherited Destroy; end;

function Keep: TCls;
begin
  WriteLn('Keep: create 2');
  Result := TCls.Create(2);
  WriteLn('Keep: return');
end;

var a, b: TCls; d: TDer; cc: TCC; p: TPlain;
begin
  WriteLn('create 1');
  a := TCls.Create(1);
  WriteLn('free 1');
  a.Free;
  b := Keep;
  WriteLn('main has b tag=', b.tag);
  WriteLn('create der 3');
  d := TDer.Create(3);
  WriteLn('der g.w=', d.g.w, ' g.s=', d.g.s);
  d.Free;
  WriteLn('metaclass 4');
  cc := TDer;
  a := cc.Create(4);
  a.Free;
  p := TPlain.Create; p.Free;
  WriteLn('free 2');
  b.Free;
  WriteLn('done');
end.
