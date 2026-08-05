{$mode objfpc}{$H+}
program test_assert_raises_with_sysutils;
{ Regression: with SysUtils in scope, a failing Assert must RAISE a catchable
  EAssertionFailed, not halt the process.

  __pxxAssert printed and Halt(227)'d unconditionally, so `try Assert(...)
  except` could never run its handler and everything after the try was lost.
  It looked correct — the message is right and 227 IS FPC's assertion exit code
  — but FPC's 227 only happens when SysUtils is NOT used.

  FPC's mechanism is a HOOK: System.AssertErrorProc defaults to print+227 and
  SysUtils REPLACES it with a raiser. Reproduced rather than reinvented, beside
  the PXXOverflowHook / PXXDivZeroHook / PXXRangeErrorHook / PXXIoErrorHook that
  already use the same ErrorProc design.

  The no-SysUtils path deliberately still halts with 227 — that is also FPC's
  behaviour, and test_assert_halts_without_sysutils would be the other half if
  the harness could express a non-zero exit.
  compat-pascal-assert-halts-instead-of-raising-eassertionfailed }
uses sysutils;
begin
  Assert(1 = 1, 'passing assert must not fire');
  writeln('passed');
  try
    Assert(1 = 2, 'boom');
    writeln('NOT REACHED');
  except
    on E: Exception do writeln('caught: ', E.ClassName, ': ', E.Message);
  end;
  try
    Assert(False);                    { no message: FPC uses a default }
  except
    on E: Exception do writeln('nomsg: ', E.ClassName, ': ', E.Message);
  end;
  writeln('still running');
  writeln('OK');
end.
