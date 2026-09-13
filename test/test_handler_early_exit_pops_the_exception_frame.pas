program TestHandlerEarlyExitPopsTheExceptionFrame;
{ An `Exit`, `Break` or `Continue` out of an `on E: T do` handler body must pop
  that handler's own exception frame.

  The handler body is a protected region in its own right -- it gets an
  IR_EXC_ENTER so the caught object survives an exception raised from INSIDE it
  (test_exception_escaping_a_handler_frees_the_caught_object is that row) -- but
  the region was pushed without a codegen depth, so IRLowerCleanupToDepth could
  not see it and the early-exit paths emitted no IR_EXC_LEAVE. The chain head
  was then a pointer into DEAD STACK.

  WHAT FAILS HERE IS THE DIAGNOSTIC, NOT A VALUE. Every WriteLn below was
  already correct while the frame leaked; the damage only shows when something
  raises with no handler left, and the unwinder longjmps into the stale frame.
  On a fresh stack that memory is zeroes, so the restore lands at
  rip=rsp=rbp=0 and the process dies on SIGSEGV printing nothing. The Makefile
  therefore greps the log for "Unhandled exception" rather than checking the
  exit code -- a segfault is nonzero too.

  AND AN ENCLOSING `try` HIDES IT COMPLETELY, which is why the final raise is
  deliberately unhandled: entering any try overwrites the chain head, so the
  same calls wrapped in `try ... except` pass on the broken compiler. The stale
  head is only ever read when nothing is above it.
  bug-a-a-return-out-of-an-except-handler-leaves-the-exception-frame-on-the-chain }

uses SysUtils;

function ExitFromHandler(k: Integer): Integer;
begin
  ExitFromHandler := -1;
  try
    raise Exception.Create('inner');
  except
    on e: Exception do begin ExitFromHandler := k * 2; Exit; end;
  end;
end;

function BreakFromHandler(k: Integer): Integer;
var i: Integer;
begin
  BreakFromHandler := 0;
  for i := 1 to 3 do
    try
      raise Exception.Create('loop');
    except
      on e: Exception do begin BreakFromHandler := k + i; Break; end;
    end;
end;

function ContinueFromHandler(k: Integer): Integer;
var i: Integer;
begin
  ContinueFromHandler := 0;
  for i := 1 to 3 do
    try
      raise Exception.Create('loop');
    except
      on e: Exception do begin ContinueFromHandler := ContinueFromHandler + 1; Continue; end;
    end;
  ContinueFromHandler := ContinueFromHandler + k;
end;

function NestedExit(k: Integer): Integer;
begin
  NestedExit := -1;
  try
    raise Exception.Create('outer');
  except
    on e: Exception do
      try
        raise Exception.Create('nested');
      except
        on f: Exception do begin NestedExit := k + 100; Exit; end;
      end;
  end;
end;

begin
  WriteLn('exit ', ExitFromHandler(3));
  WriteLn('break ', BreakFromHandler(10));
  WriteLn('continue ', ContinueFromHandler(5));
  WriteLn('nested ', NestedExit(1));
  { Nothing catches this. It is the assertion. }
  raise Exception.Create('frame chain is intact');
end.
