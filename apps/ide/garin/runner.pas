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

implementation

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

end.
