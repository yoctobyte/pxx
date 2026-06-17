program TestReactor;
{ Async-I/O reactor over the cooperative scheduler (all four hosted targets).
  A reader coroutine reads a non-blocking pipe, gets EAGAIN, parks via
  WaitReadable + yields; a writer coroutine writes after a couple of yields; the
  scheduler's epoll idle path wakes the reader once the pipe has data. Proves
  blocking I/O is concentrated into one epoll_wait/epoll_pwait, not scattered
  blocking reads. }
uses scheduler;

const
{$ifdef CPUX86_64}
  SYS_read = 0;  SYS_write = 1;  SYS_pipe2 = 293;
{$endif}
{$ifdef CPU_I386}
  SYS_read = 3;  SYS_write = 4;  SYS_pipe2 = 331;
{$endif}
{$ifdef CPU_AARCH64}
  SYS_read = 63; SYS_write = 64; SYS_pipe2 = 59;
{$endif}
{$ifdef CPU_ARM32}
  SYS_read = 3;  SYS_write = 4;  SYS_pipe2 = 359;
{$endif}

var
  pfd: array[0..1] of Integer;   { [0] = read end, [1] = write end }
  msg: array[0..1] of Byte;
  rc: Int64;

procedure Reader(arg: Pointer);
var buf: array[0..15] of Byte; n: Int64; done: Boolean;
begin
  writeln('reader: start');
  done := False;
  repeat
    n := __pxxrawsyscall(SYS_read, pfd[0], Int64(@buf[0]), 16, 0, 0, 0);   { read }
    if n = -11 then                                                  { EAGAIN }
    begin
      writeln('reader: would-block, parking');
      WaitReadable(pfd[0]);
    end
    else
      done := True;
  until done;
  writeln('reader: got ', Integer(n), ' bytes: ', Chr(buf[0]), Chr(buf[1]));
end;

procedure Writer(arg: Pointer);
begin
  CoYield;                          { let the reader run and block first }
  CoYield;
  writeln('writer: writing');
  rc := __pxxrawsyscall(SYS_write, pfd[1], Int64(@msg[0]), 2, 0, 0, 0);            { write "hi" }
end;

begin
  msg[0] := Ord('h');
  msg[1] := Ord('i');
  { pipe2(pfd, O_NONBLOCK) — both ends non-blocking }
  rc := __pxxrawsyscall(SYS_pipe2, Int64(@pfd[0]), $800, 0, 0, 0, 0);
  Spawn(@Reader, nil);
  Spawn(@Writer, nil);
  RunUntilDone;
  writeln('done');
end.
