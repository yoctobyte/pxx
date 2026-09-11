program lib_termio_isatty;
{ termio.IsATTY, grown for the FPC-compiler-source march: comptty.pas:66 calls
  `termio.IsATTY(t)=1` and that was the wall rgobj and aasmbase stopped at.

  THE ROWS OPEN THEIR OWN FILE DESCRIPTORS AND ASSERT NOTHING ABOUT stdout.
  That is deliberate twice over. `IsATTY(Output)` answers 1 under a terminal and
  0 under a pipe, so a harness that captures output can only ever see the 0 —
  and 0 is also what a stub, a failed ioctl and an invalid fd return, so such a
  row cannot fail. A pty master opened here answers 1 no matter how the test was
  invoked, which gives the suite a row whose expected value is NOT the failure
  value.

  /dev/null IS THE ROW THAT EARNS ITS PLACE. It is a character device and it is
  not a terminal, so an implementation written as fstat+S_ISCHR — the obvious
  wrong one, named in pxxcio.pas's own comment — answers 1 here and would pass
  every other row in this file. This is the row that says we ask TCGETS.

  Values checked against fpc 3.2.2 on this same source: it agrees on all of
  them, and on IsATTY(Output) through both a pipe and a pty. }
uses platform, termio;

var
  fails: Integer;

procedure Check(const nm: AnsiString; got, want: Integer);
begin
  if got = want then WriteLn(nm, '=yes')
  else begin WriteLn(nm, '=NO got ', got, ' want ', want); Inc(fails); end;
end;

var
  ptm, devnull: Integer;

begin
  fails := 0;

  { A pty master is a terminal. Answers 1 however this program was invoked. }
  ptm := PalOpen('/dev/ptmx', PAL_OPEN_RDWR, 0);
  if ptm < 0 then
  begin
    WriteLn('ptmx-open=NO got ', ptm);
    Inc(fails);
  end
  else
  begin
    Check('ptmx-is-a-tty', IsATTY(ptm), 1);
    PalClose(ptm);
  end;

  { A character device that is NOT a terminal. An fstat+S_ISCHR implementation
    answers 1 here; TCGETS answers 0. }
  devnull := PalOpen('/dev/null', PAL_OPEN_RDWR, 0);
  if devnull < 0 then
  begin
    WriteLn('devnull-open=NO got ', devnull);
    Inc(fails);
  end
  else
  begin
    Check('devnull-is-not-a-tty', IsATTY(devnull), 0);
    PalClose(devnull);
  end;

  { An fd nothing opened. }
  Check('closed-fd-is-not-a-tty', IsATTY(999), 0);

  { The `var f: Text` overload reaches the same answer through f.Handle.
    fpc declares both (rtl/unix/termiosh.inc:31-32), both returning cint. }
  Check('text-overload-agrees', IsATTY(Output), IsATTY(1));

  WriteLn('fails=', fails);
  if fails = 0 then WriteLn('TERMIO OK') else WriteLn('TERMIO FAIL');
end.
