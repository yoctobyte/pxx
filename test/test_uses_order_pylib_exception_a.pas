program TestUsesOrderPylibExceptionA;
{ bug-pascal-uses-order-breaks-pylib-exception / bug-pascal-uses-is-transitive:
  sysutils named BEFORE pylib. `Exception` is now sysutils' class and ONLY
  sysutils' — pylib's Python root was renamed PyException
  (decide-pylib-exception-vs-sysutils-exception option 5), so the name has one
  meaning here instead of resolving to whichever unit registered first.
  Which unit is named first must not change what compiles, what runs, or what
  CreateFmt prints. Companion test_uses_order_pylib_exception_b.pas runs the
  same checks with the uses clause reversed and must produce the IDENTICAL
  output — that equality is the whole test. }
uses sysutils, pylib;

var
  e: Exception;

begin
  { Constructs, and Create's body must see its own `msg` field. }
  e := Exception.Create('pylib hi');
  WriteLn(e.Message);

  { sysutils' own Exception surface, reached through a real RTL raise. }
  try
    StrToInt('abc');
  except
    on ex: Exception do
      WriteLn('caught: ', ex.Message);
  end;

  { `Exception` is sysutils' class, so CreateFmt runs SYSUTILS' body (FPC
    Format(), which pads a width spec like %5d) -- in EITHER uses order. It
    used to run whichever unit registered first, so this line printed `[%5d]`
    or `[    3]` depending on the clause above. }
  e := Exception.CreateFmt('[%5d]', [3]);
  WriteLn(e.Message);

  WriteLn('end');
end.
