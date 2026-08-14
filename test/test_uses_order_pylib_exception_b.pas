program TestUsesOrderPylibExceptionB;
{ feature-a-one-exception-class-in-a-shared-unit: pylib named BEFORE sysutils.

  BOTH units now export a class named `Exception` — siblings under the shared
  `ExceptionBase` — so the property this pair asserts had to change, and the
  new one is stronger than the old.

  OLD: bare `Exception` means sysutils' class in either order. That only held
  while pylib's root was named `PyException`, i.e. while the name had exactly
  one owner. It is not a property a language can offer once two units export
  one name: FPC itself resolves such a collision by uses order (measured
  against the oracle — the LAST unit named wins), so "order carries no
  meaning" is not FPC behaviour, it is what you get when there is no
  collision.

  NEW: the QUALIFIED name reaches the unit it names, in either order. That is
  the property that actually matters, it is what a program can rely on, and it
  is real work — `sysutils.Exception` used to resolve flat to whichever class
  registered first, so the qualifier was punctuation and a qualified reference
  silently built the wrong class.

  Companion test_uses_order_pylib_exception_a.pas runs the identical checks
  with the uses clause reversed and must produce the IDENTICAL output. That
  equality is still the whole test — it just now proves it about the qualified
  form rather than the bare one.

  The BARE name under a collision is deliberately NOT asserted here: it is
  order-dependent by FPC's own rule, and pxx currently resolves it first-match
  where FPC resolves it last-match. That divergence is its own ticket
  (bug-pascal-uses-clause-duplicate-name-resolves-first-not-last) and is much
  wider than exceptions. }
uses pylib, sysutils;

var
  e: sysutils.Exception;
  p: pylib.Exception;
  v: Variant;

begin
  { Constructs sysutils' class, and Create's body must see the `msg` it
    inherits from ExceptionBase. }
  e := sysutils.Exception.Create('su hi');
  WriteLn(e.Message);

  { sysutils' own Exception surface, reached through a real RTL raise. The
    handler names the SHARED ROOT, which is what makes one arm catch both
    trees now that the frontend bridge is gone. }
  try
    StrToInt('abc');
  except
    on ex: ExceptionBase do
      WriteLn('caught: ', ex.Message);
  end;

  { The qualified name selects sysutils' CreateFmt — the one that calls the
    real Format and pads a width spec. pylib's sibling does minimal
    substitution and would print `[%5d]`, so this line is what proves the
    qualifier reached the right class's METHOD and not merely the right class:
    class resolution and method resolution were two separate flat lookups. }
  e := sysutils.Exception.CreateFmt('[%5d]', [3]);
  WriteLn(e.Message);

  { ...and the same qualifier reaches PYLIB's class in the same program. Its
    ctor takes a Variant (Python's `Exception(obj)` accepts any object), so the
    argument goes through a Variant rather than a literal. }
  v := 'py hi';
  p := pylib.Exception.Create(v);
  WriteLn(p.msg);

  { Both are named `Exception` — that is what makes Python's repr(e) and
    type(e).__name__ come out right with no rename in the frontend. }
  WriteLn(e.ClassName, ' ', p.ClassName);

  WriteLn('end');
end.
