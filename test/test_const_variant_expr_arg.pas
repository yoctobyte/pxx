{ bug-a-const-variant-arg-expression-fails-outside-pyexprmode: an expression
  argument (not a bare lvalue) to a `const Variant` PARAMETER must compile in
  plain Pascal, not only under NilPy. Two independent bugs, both fixed here:
  ByRefArgStartsExpression only ran its expression-vs-lvalue check under
  PyExprMode, and separately a parameter-array SHIFT (making room for Self at
  index 0 in a method implementation) silently dropped the `const` flag one
  slot off, so ProcParamIsConst read False for a method's real `const`
  parameter regardless of the first fix. pylib's own TPyList.append hit the
  second bug directly: `pair.append(start + i)` inside pylib.pas itself. }
program TestConstVariantExprArg;
uses pylib;
var
  r: TPyList;
  start, i: Integer;
begin
  r := TPyList.Create;
  start := 10;
  i := 5;
  r.append(start + i);      { expression arg to TPyList.append(const v: Variant) }
  if r.count = 1 then WriteLn('ok') else WriteLn('FAIL');
end.
