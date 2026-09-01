program TestExceptionObjectLeaks;
{ Every CAUGHT exception object must be freed at handler exit, and nothing that
  is not an object may be freed at all.

  The constructor's one reference is TRANSFERRED by `raise` -- it is not an
  extra one -- so if the handler does not drop it, every caught exception leaks
  its instance forever. Measured before the fix (frankB 2026-09-01), 1500
  raises in a loop: allocs=1478 frees=0 live=1478 on x86-64 and aarch64,
  3000/0 on i386/arm32/riscv32. Both Pascal shapes leaked, bare `except` and
  `on E: T do` alike, for two different reasons: the owning-temp arm was gated
  to NilPy, and a Pascal class-typed binder local is manually managed so its
  scope exit releases nothing.

  THE TWO ARMS BELOW ARE NOT THE SAME CHECK, and the second is the one that is
  easy to lose. `raise <Integer>` is legal in this dialect (FPC rejects it; we
  accept it, which is not a defect) and then the in-flight "exception" is a
  VALUE, not a pointer -- freeing it walks 42 as a heap block and segfaults.
  A version of this fix that freed unconditionally passed every leak assertion
  here and took test_cross_exception.pas down with a SIGSEGV. So the integer
  arm is the guard's positive control: it must survive, and it must print.

  Run under -dPXX_ALLOC_CENSUS, tools/assert_no_leak.sh bounds live objects
  absolutely -- not against another backend, because before the fix EVERY
  backend leaked and a differential would have compared two wrong numbers. }

uses SysUtils;

type
  EBoom = class(Exception);

var
  i, caughtObj, caughtInt, caughtReraise, msgOk: Integer;
  s: AnsiString;

procedure RaiseInt(v: Integer);
begin
  raise v;
end;

begin
  caughtObj := 0; caughtInt := 0; caughtReraise := 0; msgOk := 0;

  { arm 1 -- bare `except`: no binder, so nothing in user code could ever
    release it even in principle. }
  for i := 1 to 1500 do
  begin
    try
      raise EBoom.Create('boom');
    except
      caughtObj := caughtObj + 1;
    end;
  end;

  { arm 2 -- `on E: T do` binder, and the field read that proves the object is
    still intact INSIDE the handler (a free hoisted too early would corrupt
    this before it is read). }
  for i := 1 to 1500 do
  begin
    try
      raise EBoom.Create('boom');
    except
      on E: EBoom do
      begin
        s := E.Message;
        if s = 'boom' then msgOk := msgOk + 1;
      end;
    end;
  end;

  { arm 3 -- re-raise. The inner handler must NOT free an object that is still
    in flight; the outer one must free it exactly once. }
  for i := 1 to 1500 do
  begin
    try
      try
        raise EBoom.Create('boom');
      except
        on E: EBoom do
        begin
          caughtReraise := caughtReraise + 1;
          raise;
        end;
      end;
    except
      caughtObj := caughtObj + 1;
    end;
  end;

  { arm 4 -- THE POSITIVE CONTROL: a non-object raise must be caught and must
    NOT be freed. If the handler's free is unguarded this segfaults. }
  for i := 1 to 1500 do
  begin
    try
      RaiseInt(42);
    except
      caughtInt := caughtInt + 1;
    end;
  end;

  Writeln('obj ', caughtObj);
  Writeln('msg ', msgOk);
  Writeln('reraise ', caughtReraise);
  Writeln('int ', caughtInt);
end.
