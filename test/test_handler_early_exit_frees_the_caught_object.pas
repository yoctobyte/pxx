program TestHandlerEarlyExitFreesTheCaughtObject;
{ The leak half of test_handler_early_exit_pops_the_exception_frame.

  Leaving a handler body through `Exit`, `Break` or `Continue` skipped the
  handler region's IR_EXC_LEAVE, and with it the free of the object that
  handler was holding and the clear of the exception slots. Every value below
  was right the whole time -- a leak does not corrupt, it just never gives the
  memory back -- so tools/assert_no_leak.sh is the instrument and the printed
  counters are for a human reading a failure.

  MEASURED, same file both ways, pin v409 against HEAD: allocs=5411 on both,
  frees=408 live=5003 pinned and frees=5408 live=3 at HEAD. The ALLOC side does
  not move at all -- only the free side -- which is what makes this a leak row
  and not an allocation-count row, and the four printed values are byte-identical
  in both runs, which is what makes tools/assert_no_leak.sh the instrument.
  bug-a-a-return-out-of-an-except-handler-leaves-the-exception-frame-on-the-chain }

uses SysUtils;

const TRIPS = 500;

function ExitFromHandler(k: Integer): Integer;
begin
  ExitFromHandler := -1;
  try
    raise Exception.Create('inner-' + Chr(48 + k mod 10));
  except
    on e: Exception do begin ExitFromHandler := k; Exit; end;
  end;
end;

function BreakFromHandler(k: Integer): Integer;
var i: Integer;
begin
  BreakFromHandler := 0;
  for i := 1 to 3 do
    try
      raise Exception.Create('loop-' + Chr(48 + k mod 10));
    except
      on e: Exception do begin BreakFromHandler := k; Break; end;
    end;
end;

function ContinueFromHandler(k: Integer): Integer;
var i: Integer;
begin
  ContinueFromHandler := 0;
  for i := 1 to 3 do
    try
      raise Exception.Create('cont-' + Chr(48 + k mod 10));
    except
      on e: Exception do begin ContinueFromHandler := ContinueFromHandler + 1; Continue; end;
    end;
end;

{ THE CONTROL: a handler that falls out the bottom. It was always clean, so a
  fix that double-frees or clears the wrong slots shows up here as a crash or a
  negative live count rather than as a passing row. }
function PlainHandler(k: Integer): Integer;
begin
  PlainHandler := 0;
  try
    raise Exception.Create('plain-' + Chr(48 + k mod 10));
  except
    on e: Exception do PlainHandler := k;
  end;
end;

var i, a, b, c, d: Integer;
begin
  a := 0; b := 0; c := 0; d := 0;
  for i := 1 to TRIPS do a := a + ExitFromHandler(1);
  for i := 1 to TRIPS do b := b + BreakFromHandler(1);
  for i := 1 to TRIPS do c := c + ContinueFromHandler(1);
  for i := 1 to TRIPS do d := d + PlainHandler(1);
  WriteLn('exit ', a);
  WriteLn('break ', b);
  WriteLn('continue ', c);
  WriteLn('plain ', d);
  WriteLn('HANDLEREXIT OK');
end.
