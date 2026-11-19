program test_mgmt_operators_class_field_refused;
{ A DYNAMIC array of a management-operator record inside a class field is
  refused: its elements come and go with SetLength, not with the object, so the
  class layout descriptor has nothing fixed to walk. Every fixed shape -- a
  plain field, a fixed array, a record nested at any depth -- runs at
  Create/Free (test_mgmt_operators_class_field*.pas).

  The class is constructed through an ANCESTOR-typed variable on purpose: the
  refusal used to be checked only at a variable of the class's own type, so
  this exact program compiled and silently skipped its Initialize.

  Re-aimed twice: it refused the direct shape until 2026-11-20 and the nested
  shape until the flattening landed the same day.
  feature-pascal-management-operators-on-a-class-field }
{$mode objfpc}{$modeswitch advancedrecords}
type
  TFoo = record
    n: Integer;
    class operator Initialize(var a: TFoo);
  end;
  TW = record
    d: array of TFoo;
  end;
  TBase = class end;
  TCls = class(TBase)
    w: TW;
  end;
class operator TFoo.Initialize(var a: TFoo);
begin a.n := 1; end;
var b: TBase;
begin
  b := TCls.Create;
  b.Free;
end.
