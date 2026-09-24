{ SizeOf of a CLASS TYPE is the width of a reference to it, the same as SizeOf
  of a variable of that type -- not the instance size, which is InstanceSize.
  The type spelling answered RecSize (the instance), so with three Int64
  fields SizeOf(TFoo) was 32 where fpc says 8 and the variable said 8, and
  `Move(a, b, SizeOf(TFoo))` on two references copied 32 bytes out of an
  8-byte variable. The fields are there so the instance size cannot collide
  with the reference width. Every row is a RELATION, so no width is pinned.

  Spellings: the class, an alias of it, a generic specialisation, a nested
  class, a const expression, and a Move through it -- plus two value types
  that must keep their full size (a record, an `object`). }
{$mode objfpc}
program test_sizeof_of_a_class_type_is_the_reference_width;
type
  TFoo = class a, b, c: Int64; end;
  TAlias = TFoo;
  generic TG<T> = class a, b, c: T; end;
  TGI = specialize TG<Int64>;
  TOuter = class
  type TInner = class a, b, c: Int64; end;
  end;
  TRec = record a, b, c: Int64; end;
  TOb = object a, b, c: Int64; end;
const KFoo = SizeOf(TFoo);
var f, g: TFoo; guard: Int64; r: TRec; ob: TOb; inner: TOuter.TInner;
begin
  f := TFoo.Create; f.a := 7; g := nil; guard := 12345;
  Move(f, g, SizeOf(TFoo));
  WriteLn(SizeOf(TFoo) = SizeOf(f), ' ', SizeOf(TAlias) = SizeOf(f), ' ',
          SizeOf(TGI) = SizeOf(f), ' ', SizeOf(TOuter.TInner) = SizeOf(inner), ' ',
          KFoo = SizeOf(f), ' ', SizeOf(TFoo) = SizeOf(Pointer));
  WriteLn(TFoo.InstanceSize > SizeOf(TFoo), ' ', SizeOf(TRec) = SizeOf(r), ' ',
          SizeOf(TOb) = SizeOf(ob), ' ', SizeOf(TRec) = 3 * SizeOf(Int64), ' ',
          SizeOf(TOb) = 3 * SizeOf(Int64));
  WriteLn(g.a, ' ', guard);
  f.Free;
end.
