program TestUsesOrderPylibExceptionB;
{ bug-pascal-uses-order-breaks-pylib-exception / bug-pascal-uses-is-transitive:
  same checks as test_uses_order_pylib_exception_a.pas, but pylib named BEFORE
  sysutils. The two files must produce IDENTICAL output; the pair exists to
  prove uses order carries no meaning here. }
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

  { pylib registers FIRST here and it makes no difference: `Exception` is
    sysutils' class either way, so CreateFmt pads. This line printed `[%5d]`
    before pylib's root was renamed PyException, which is exactly the
    order-dependence the pair was written to catch. }
  e := Exception.CreateFmt('[%5d]', [3]);
  WriteLn(e.Message);

  WriteLn('end');
end.
