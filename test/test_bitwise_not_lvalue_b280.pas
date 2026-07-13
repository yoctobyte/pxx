{ Unary `not` on an ARRAY ELEMENT, a FIELD or a DEREF must be BITWISE, not boolean.

  Whether `not x` is bitwise or logical is decided from the operand's node kind: PXX tags
  some nodes (comparisons, boolean-returning calls) tyInteger even when they are logically
  Boolean, so only node shapes whose integer type is AUTHORITATIVE may be trusted. The list
  had AN_INT_LIT, AN_IDENT, value-casts and arithmetic binops -- but NOT an array element,
  a field, or a deref, whose declared element/field/pointee type is exactly as trustworthy
  as a variable's.

  So `not arr[i]` was lowered as a BOOLEAN not. It printed TRUE. And `mask[i] and not
  rhs[i]` silently produced garbage -- bit manipulation on array elements (bitmasks,
  hashing, crypto) was quietly wrong, while the identical code on a plain variable was
  right. That asymmetry is what makes it worth a regression: the obvious way to test `not`
  is on a variable, which always worked.

  A genuine Boolean element still goes logical -- that is the tyBoolean guard, asserted
  below. }
program test_bitwise_not_lvalue_b280;

type
  TRec = record
    B: Byte;
    I: Integer;
  end;
  PInt = ^Integer;

var
  ab: array[0..3] of Byte;
  ai: array[0..3] of Integer;
  a64: array[0..3] of Int64;
  abool: array[0..3] of Boolean;
  r: TRec;
  v: Integer;
  p: PInt;
begin
  ab[0] := 2;  ai[0] := 2;  a64[0] := 2;
  r.B := 2;    r.I := 2;
  v := 2;      p := @v;

  { the operation that was silently wrong: mask AND NOT other }
  writeln('byte elem : ', 7 and not ab[0],  ' (5)');
  writeln('int elem  : ', 7 and not ai[0],  ' (5)');
  writeln('int64 elem: ', 7 and not a64[0], ' (5)');
  writeln('rec byte  : ', 7 and not r.B,    ' (5)');
  writeln('rec int   : ', 7 and not r.I,    ' (5)');
  writeln('deref     : ', 7 and not p^,     ' (5)');
  writeln('plain var : ', 7 and not v,      ' (5)');

  { `not` alone on an element is a bitwise complement, not TRUE/FALSE }
  writeln('not elem  : ', not ai[0]);
  writeln('not var   : ', not v);

  { ...but a Boolean element is still LOGICAL }
  abool[0] := False;
  writeln('bool elem : ', not abool[0], ' (TRUE)');
  abool[1] := True;
  writeln('bool elem2: ', not abool[1], ' (FALSE)');
end.
