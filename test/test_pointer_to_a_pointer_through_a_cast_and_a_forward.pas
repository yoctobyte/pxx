program test_pointer_to_a_pointer_through_a_cast_and_a_forward;
{ A DOUBLE pointer, reached three ways, in both declaration ORDERS.

  Two independent defects met here, and both were silent or order-dependent:

  1. `PPRec(pp)^^.f` — a cast, then two derefs. The pointer-alias cast in
     ParseFactorCore ran its own suffix walk built on NodePtrElem, which knows
     only the IMMEDIATE pointee, so the deref nodes carried no remaining depth
     and no ultimate base record. ResolveNodeRec then answered REC_NONE and
     every trailing field resolved at OFFSET 0 — `PPOut(pp)^^.inner.y` printed
     `r.a`. The same chain WITHOUT the cast was right, because that spelling
     goes through ParseLValueAST, which asks ResolveDerefShape.

  2. `PPInt = ^PInt;` written ABOVE `PInt = ^Integer;` — the forward order,
     which is how rtl-generics' Generics.Defaults spells its VMT pointers. The
     alias kept depth 1, so the SECOND `^` was refused with `dereferenced value
     is not a pointer`. Swapping the two declarations made the same program
     compile.

  Both orders and all three spellings are asserted, so neither can regress
  alone. .expected IS fpc 3.2.2's own output on this source. }
{$mode delphi}

type
  { forward order: the double pointer is declared BEFORE its pointee alias }
  PPFwd = ^PFwd;
  PFwd  = ^Integer;

  TIn  = record x, y: Integer; end;
  TOut = record a: Integer; inner: TIn; end;
  { natural order }
  POut  = ^TOut;
  PPOut = ^POut;

  TFactory = class public class function Name: string; virtual; end;
  TFactoryClass = class of TFactory;
  TVmt = packed record ClassRef: TFactoryClass; end;
  PVmt  = ^TVmt;
  PPVmt = ^PVmt;

class function TFactory.Name: string; begin Result := 'factory'; end;

var
  n: Integer; pf: PFwd; ppf: PPFwd;
  r: TOut; po: POut; ppo: PPOut;
  v: TVmt; pv: PVmt; ppv: PPVmt;
begin
  n := 42; pf := @n; ppf := @pf;
  WriteLn('fwd    : ', pf^, ' ', ppf^^);

  r.a := 1; r.inner.x := 5; r.inner.y := 9;
  po := @r; ppo := @po;
  WriteLn('plain  : ', po^.inner.y, ' ', ppo^^.inner.y);
  { the cast spelling — the one that answered r.a }
  WriteLn('cast   : ', POut(po)^.inner.y, ' ', PPOut(ppo)^^.inner.y);
  WriteLn('mixed  : ', PPOut(ppo)^^.a, ' ', PPOut(ppo)^^.inner.x);

  v.ClassRef := TFactory; pv := @v; ppv := @pv;
  { a metaclass reached through the double pointer, then a virtual class
    method on it — the Generics.Defaults hash-factory idiom }
  WriteLn('meta   : ', ppv^^.ClassRef.Name, ' ', PPVmt(ppv)^^.ClassRef.Name);
end.
