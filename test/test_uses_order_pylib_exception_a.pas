program TestUsesOrderPylibExceptionA;
{ bug-pascal-uses-order-breaks-pylib-exception: sysutils named BEFORE pylib.
  Both units declare a class literally named `Exception`; the name is
  deliberately shared program-wide (ClassNameIsDeliberatelyShared) so a bare
  `except Exception:` catches either RTL's raise. That shared-name bypass was
  ALSO catching the `ClassName.MethodName` impl-header lookup, so whichever
  unit's `Exception` registered second had its OWN constructor bodies bound to
  the OTHER unit's class -- pylib's `Exception.Create` resolving `msg` against
  sysutils' class and reporting "undefined variable (msg)". Which unit is
  named first must not change whether either surface compiles or runs.
  Companion file test_uses_order_pylib_exception_b.pas runs the same checks
  with the uses clause reversed. }
uses sysutils, pylib;

var
  e: Exception;

begin
  { pylib's own Exception surface: constructs, and Create's body must see its
    own `msg` field. }
  e := Exception.Create('pylib hi');
  WriteLn(e.Message);

  { sysutils' own Exception surface, reached through a real RTL raise. }
  try
    StrToInt('abc');
  except
    on ex: Exception do
      WriteLn('caught: ', ex.Message);
  end;

  { The shared `Exception` name flat-resolves to whichever unit registered
    FIRST -- here sysutils, so bare `Exception.CreateFmt` must run SYSUTILS'
    own body (FPC Format(), which pads a width spec like %5d) and not have
    been silently overwritten by pylib's own CreateFmt body (which leaves an
    unsupported spec like %5d VERBATIM) binding to the wrong class row --
    the actual corruption this bug caused before the fix. }
  e := Exception.CreateFmt('[%5d]', [3]);
  WriteLn(e.Message);

  WriteLn('end');
end.
