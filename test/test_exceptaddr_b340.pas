{ ExceptAddr: the code address of the RAISE SITE of the exception in flight (b340).

  It used to be a declared STUB returning nil — defensible (its callers are
  diagnostic, and fpcunit prints "n/a" for a nil address) but a lie waiting to
  become folklore.

  The information was already on the stack: the `call` to the raise stub pushes the
  raise site itself, so at stub entry the return address IS the instruction after
  the `raise`. The stub now parks it in a BSS slot, and __pxxExceptAddr (which
  sysutils.ExceptAddr wraps) loads it — the same load `on E:` uses for the exception
  OBJECT, just a different slot.

  Checked here: nil when nothing is in flight; a real code address INSIDE the routine
  that raised; distinct sites give distinct addresses; and nil again after the handler
  (the address slot is cleared with the object slot — an address that outlived its
  exception would be exactly the kind of stale value that reads as working). }
program test_exceptaddr_b340;
{$mode objfpc}{$h+}
uses SysUtils;

var
  fails: Integer;
  a1, a2: Pointer;
  boomLo: PtrUInt;

procedure Check(const what: AnsiString; ok: Boolean);
begin
  if ok then writeln('ok   ', what)
  else
  begin
    writeln('FAIL ', what);
    fails := fails + 1;
  end;
end;

procedure Boom;
begin
  raise Exception.Create('boom');
end;

begin
  fails := 0;
  boomLo := PtrUInt(@Boom);

  { nothing in flight }
  Check('nil before any raise', ExceptAddr = nil);

  try
    Boom;
  except
    on E: Exception do a1 := ExceptAddr;
  end;

  Check('non-nil inside the handler', a1 <> nil);

  { The raise sits inside Boom, so the recorded site must land after Boom's entry.
    4K is a generous ceiling on a three-line routine — this is checking that we got
    a real code address, not that the codegen has a particular size. }
  Check('points inside the raising routine',
        (PtrUInt(a1) > boomLo) and (PtrUInt(a1) < boomLo + 4096));

  { a DIFFERENT raise site must record a different address }
  try
    raise Exception.Create('other');
  except
    on E: Exception do a2 := ExceptAddr;
  end;
  Check('non-nil for the second raise', a2 <> nil);
  Check('two raise sites give two addresses', a1 <> a2);

  { cleared with the exception object — no stale address outliving its exception }
  Check('nil again after the handler', ExceptAddr = nil);

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
