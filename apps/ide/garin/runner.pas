unit runner;
{ garin/runner — render-agnostic process runner for the IDE. Launches an external
  command (the pinned compiler, a built binary, ...) and captures its stdout
  (pxx writes diagnostics to stdout, so compiler errors are captured too).
  No GTK here — usable by any face (eliah/ilja). }

interface

uses sysutils, platform;

{ Run exe with args, capture stdout to the result, set exitCode to the child's
  exit status (0 = success). }
function RunCapture(const exe: AnsiString; const args: array of AnsiString;
                    var exitCode: Integer): AnsiString;

{ Non-blocking form, for a face that must keep painting while a child runs (a
  build+flash that takes a minute, a serial monitor that never ends). Start it,
  then call StreamPoll from a timer: each call returns whatever output is ready
  now (possibly '') and never blocks longer than timeoutMs. When the child's
  output ends, StreamPoll reaps it, sets Running := False and ExitCode.
  StreamStop kills a child that is still running (SIGTERM) and reaps it.
  The child inherits our stdin, and stdout only is captured: spell a command
  whose stderr matters as /bin/sh -c '... 2>&1'. }
type
  TStreamProc = record
    Pid: Integer;
    Fd: Integer;
    Running: Boolean;
    ExitCode: Integer;
  end;

function StreamStart(var p: TStreamProc; const exe: AnsiString;
                     const args: array of AnsiString): Boolean;
function StreamPoll(var p: TStreamProc; timeoutMs: Integer): AnsiString;
procedure StreamStop(var p: TStreamProc);

implementation

const
  POLL_IN = 1;
  POLL_HUP = 16;
  SIG_TERM = 15;

function RunCapture(const exe: AnsiString; const args: array of AnsiString;
                    var exitCode: Integer): AnsiString;
var
  pid, inFd, outFd, i, st: Integer;
  buf: array of Byte;
  n: Int64;
  res: AnsiString;
begin
  inFd := -1;
  outFd := -1;
  exitCode := -1;
  res := '';
  pid := ExecutePipeline(exe, args, inFd, outFd);
  if pid <= 0 then
  begin
    RunCapture := '(failed to launch ' + exe + ')';
    Exit;
  end;
  SetLength(buf, 8192);
  repeat
    n := PalRead(outFd, @buf[0], 8192);
    if n > 0 then
      for i := 0 to Integer(n) - 1 do res := res + Chr(buf[i]);
  until n <= 0;
  st := 0;
  PalWait4(pid, @st, 0, nil);
  exitCode := (st shr 8) and $FF;     { decode normal-exit code from wait status }
  PalClose(outFd);
  RunCapture := res;
end;

procedure StreamReap(var p: TStreamProc);
var st: Integer;
begin
  if p.Fd >= 0 then PalClose(p.Fd);
  p.Fd := -1;
  st := 0;
  if p.Pid > 0 then
  begin
    PalWait4(p.Pid, @st, 0, nil);
    if (st and $7F) = 0 then
      p.ExitCode := (st shr 8) and $FF
    else
      p.ExitCode := 128 + (st and $7F);   { killed by a signal, shell-style }
  end;
  p.Pid := 0;
  p.Running := False;
end;

function StreamStart(var p: TStreamProc; const exe: AnsiString;
                     const args: array of AnsiString): Boolean;
var inFd, outFd: Integer;
begin
  p.Pid := 0;
  p.Fd := -1;
  p.Running := False;
  p.ExitCode := -1;
  inFd := 0;          { not -1: the child inherits our stdin, no pipe made }
  outFd := -1;
  p.Pid := ExecutePipeline(exe, args, inFd, outFd);
  if p.Pid <= 0 then
  begin
    p.Pid := 0;
    StreamStart := False;
    Exit;
  end;
  p.Fd := outFd;
  p.Running := True;
  StreamStart := True;
end;

function StreamPoll(var p: TStreamProc; timeoutMs: Integer): AnsiString;
var
  buf: array of Byte;
  n: Int64;
  i, ev, reads: Integer;
  res: AnsiString;
begin
  res := '';
  StreamPoll := '';
  if not p.Running then Exit;
  SetLength(buf, 4096);
  reads := 0;
  { Drain what is ready, but cap the work per call so a chatty child cannot
    starve the face's event loop. }
  while reads < 16 do
  begin
    ev := PalPoll(p.Fd, POLL_IN, timeoutMs);
    if ev <= 0 then Break;                       { nothing ready (or error) }
    n := PalRead(p.Fd, @buf[0], 4096);
    if n > 0 then
    begin
      { presize and fill: appending a Char at a time is quadratic in the
        chunk, and a build log arrives 64 KB per poll }
      i := Length(res);
      SetLength(res, i + Integer(n));
      Move(buf[0], res[i + 1], Integer(n));
      Inc(reads);
      timeoutMs := 0;                            { only the first wait blocks }
    end
    else
    begin
      StreamReap(p);                             { EOF: the child is done }
      Break;
    end;
    if (ev and POLL_HUP) <> 0 then
      if (ev and POLL_IN) = 0 then begin StreamReap(p); Break; end;
  end;
  StreamPoll := res;
end;

procedure StreamStop(var p: TStreamProc);
begin
  if not p.Running then Exit;
  PalKill(p.Pid, SIG_TERM);
  StreamReap(p);
end;

end.
