{ A NAMED ARRAY TYPE can be an operator overload's operand type.

  `operator and (a, b: TArr)` answered `TArr is not a supported operand type`:
  OperandTypeKindRec resolved a name through records, classes, the builtin
  scalar table and the scalar ALIAS table, and an array type is in none of them
  -- arrays live in their own ArrType* tables.

  ROW 2 IS THE ONE THAT MATTERS AND IT IS A POSITIVE CONTROL, not a second
  feature. An array's TypeKind IS its element kind, so the obvious fix --
  register TArr under tyChar -- makes `array of Char` and `Char` the SAME
  (kind, recId) row in a table keyed on those two. Measured with exactly that
  fix in place: pxx warned `operator is already overloaded for these operand
  types` at the declaration, then ran the ARRAY body for `c and d` on two
  Chars and SEGFAULTED inside Length. REC_ARRAY_OPERAND is what separates the
  two rows, and this file fails loudly if it stops.

  Both rows are fpc 3.2.2-identical. bug-p-an-enum-or-array-type-cannot-be-named-as-an-operator-operand }
{$mode objfpc}{$H+}
program test_operator_array_operand;
type
  TArr = array of Char;
  TNums = array of LongInt;
operator and (const a, b: TArr) res: LongInt;
begin res := Length(a) + Length(b); end;
operator and (const a, b: Char) res: LongInt;
begin res := Ord(a) + Ord(b); end;
operator + (const a, b: TNums) res: LongInt;
begin res := Length(a) * 100 + Length(b); end;

var
  x, y: TArr;
  p, q: TNums;
  c, d: Char;
begin
  SetLength(x, 2); SetLength(y, 3);
  SetLength(p, 4); SetLength(q, 5);
  c := 'A'; d := 'B';
  WriteLn('1 array of Char     ', x and y);
  WriteLn('2 plain Char        ', c and d);
  WriteLn('3 array of LongInt  ', p + q);
end.
