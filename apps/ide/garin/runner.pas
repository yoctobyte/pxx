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
{ Make arbitrary child/serial bytes safe to put in a UTF-8 text widget:
  invalid sequences and NUL become '?'/dropped. See the implementation. }
function SanitizeUtf8ForText(const s: AnsiString): AnsiString;
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
  { O_NONBLOCK ON THE CHILD'S STDOUT, and this is design rather than defence.
    StreamPoll's whole contract is that it never blocks longer than timeoutMs,
    because a GUI event loop calls it from a timer tick: a read that waits is a
    frozen window. Asking poll first and trusting the answer makes that contract
    depend on poll and read agreeing about the fd, and espide has been observed
    wedged in read() on this pipe with poll saying nothing was ready and the
    pipe empty (bug-s-espide-auto-never-exits-after-build-flash). With the fd
    non-blocking, read() answers EAGAIN instead of sleeping, so the contract
    holds whether or not that disagreement is understood.
    PalSetSocketNonBlocking is fcntl(F_SETFL, O_NONBLOCK) -- an fd operation,
    not a socket one, despite the name. }
  if p.Fd >= 0 then PalSetSocketNonBlocking(p.Fd, 1);
  p.Running := True;
  StreamStart := True;
end;

{ A SERIAL PORT DELIVERS BYTES, AND A GtkTextView DEMANDS UTF-8. Feeding it raw
  serial output is a real defect, observed on a live classic ESP32:

    Gtk-CRITICAL: gtk_text_buffer_emit_insert:
                  assertion 'g_utf8_validate (text, len, NULL)' failed

  A board emits non-UTF-8 for ordinary reasons -- the ROM's first bytes at a
  different baud than the monitor, a half-received frame, a program printing
  binary -- so this is the normal case, not a corrupt one. GTK rejects the whole
  insert, so the pane silently loses the chunk, and an insert that fails its own
  assertion leaves the buffer in a state nothing here should rely on.

  NUL matters separately from validity: the text reaches GTK as a C string, so a
  single #0 would truncate everything after it in that chunk.

  Only the DISPLAYED text is sanitised. What goes to stdout stays raw (bar CR), because a
  headless run's log is a capture of what the board actually said and must not be
  quietly edited. }
function SanitizeUtf8ForText(const s: AnsiString): AnsiString;
var i, n, need, j: Integer;
    r: AnsiString;
    b: Byte;
    ok: Boolean;
begin
  SetLength(r, Length(s));
  n := 0;
  i := 1;
  while i <= Length(s) do
  begin
    b := Byte(s[i]);
    if b = 0 then
    begin
      { drop it: it would truncate the C string GTK receives }
      Inc(i);
      Continue;
    end;
    if b < $80 then
    begin
      Inc(n); r[n] := s[i]; Inc(i);
      Continue;
    end;
    { how many continuation bytes this lead byte promises }
    if      (b and $E0) = $C0 then need := 1
    else if (b and $F0) = $E0 then need := 2
    else if (b and $F8) = $F0 then need := 3
    else                           need := -1;
    ok := need > 0;
    if ok then
      for j := 1 to need do
        if (i + j > Length(s)) or ((Byte(s[i + j]) and $C0) <> $80) then
        begin
          ok := False;
          Break;
        end;
    if ok then
    begin
      for j := 0 to need do
      begin
        Inc(n); r[n] := s[i + j];
      end;
      Inc(i, need + 1);
    end
    else
    begin
      { one '?' per offending byte: the pane stays byte-countable against the
        raw log, which matters when comparing the two after a garbled boot }
      Inc(n); r[n] := '?'; Inc(i);
    end;
  end;
  SetLength(r, n);
  SanitizeUtf8ForText := r;
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
    { EAGAIN IS NOT EOF, and the distinction is the whole point of the
      non-blocking fd: n <= 0 below reaps the child, so treating "no data right
      now" as "the child is done" would kill a live monitor on its first quiet
      tick. Only a genuine 0 (writer closed) means EOF; any other negative is a
      real error and also ends the stream. }
    if n = PAL_NET_EAGAIN then Break;
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
