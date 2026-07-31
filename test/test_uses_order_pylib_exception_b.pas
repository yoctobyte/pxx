program TestUsesOrderPylibExceptionB;
{ bug-pascal-uses-order-breaks-pylib-exception: same checks as
  test_uses_order_pylib_exception_a.pas, but pylib named BEFORE sysutils --
  the uses order that used to compile, while the reverse order failed inside
  pylib's own Exception.Create. With the fix, a `ClassName.MethodName` impl
  header always binds to a class declared in the CURRENT unit regardless of
  ClassNameIsDeliberatelyShared, so both orders behave the same. }
uses pylib, sysutils;

var
  e: Exception;

begin
  e := Exception.Create('pylib hi');
  WriteLn(e.Message);

  try
    StrToInt('abc');
  except
    on ex: Exception do
      WriteLn('caught: ', ex.Message);
  end;

  { Here pylib registers FIRST, so bare `Exception.CreateFmt` must run
    PYLIB's own body (its minimal %s/%d substitution, which leaves an
    unsupported spec like %5d VERBATIM) and not have been overwritten by
    sysutils' CreateFmt body (FPC Format(), which would pad it) binding to
    the wrong class row -- the mirror image of the corruption
    test_uses_order_pylib_exception_a.pas checks for the other order. }
  e := Exception.CreateFmt('[%5d]', [3]);
  WriteLn(e.Message);

  WriteLn('end');
end.
