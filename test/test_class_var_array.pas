program test_class_var_array;
{ A `class var` takes every type a plain `var` does — arrays above all.

  It used to be parsed by a two-liner of its own (`ParseTypeKind + AllocVar`)
  that could not express an array: an INLINE `array[...] of T` was `unknown
  type: array`, and a NAMED array type reached AllocVar as a SCALAR, so it
  indexed correctly while `Length()` answered garbage with no diagnostic and
  `SizeOf` / `SetLength` / `TC.F[0]` each failed their own way.
  bug-p-a-class-var-takes-no-array-type-and-a-named-one-is-silently-a-scalar.

  Every line below is FPC-differential: fpc 3.2.2 prints exactly this. }
{$mode objfpc}{$H+}
type
  TA = array[0..3] of Integer;
  TB = class
    class var Named   : TA;                        { named fixed array }
    class var Inline_ : array[0..2] of Integer;    { inline fixed array }
    class var ND      : array[0..1, 0..2] of Integer;   { inline N-D }
    class var Dyn     : array of Integer;          { dynamic }
    class var Ptr     : ^Integer;                  { non-array types keep working }
    class var Bits    : set of Byte;
    class procedure Go;
  end;
  TD = class(TB) end;   { a subclass sees the inherited class var }
var b: TB; n: Integer;

class procedure TB.Go;
begin
  { bare, unqualified, inside a class method }
  Named[1] := 11;
  Inline_[2] := 7;
  ND[1, 2] := 9;
  SetLength(Dyn, 3);
  Dyn[2] := 8;
  WriteLn('bare ', Named[1], ' ', Length(Named), ' ', SizeOf(Named));
  WriteLn('inline ', Inline_[2], ' ', Length(Inline_));
  WriteLn('nd ', ND[1, 2]);
  WriteLn('dyn ', Length(Dyn), ' ', Dyn[2]);
end;

begin
  TB.Go;
  TB.Named[2] := 22;                { class-QUALIFIED, as an lvalue }
  WriteLn('qual ', TB.Named[1], ' ', TB.Named[2], ' ', Length(TB.Named));
  b := TB.Create;
  WriteLn('inst ', b.Named[1], ' ', Length(b.Named));
  WriteLn('inherited ', TD.Named[1], ' ', Length(TD.Named));
  n := 5; TB.Ptr := @n;
  TB.Bits := [1, 3];
  WriteLn('other ', TB.Ptr^, ' ', 2 in TB.Bits, ' ', 3 in TB.Bits);
  b.Free;
  WriteLn('CLASS VAR ARRAY OK');
end.
