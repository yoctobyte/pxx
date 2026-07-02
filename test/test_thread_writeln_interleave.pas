program test_thread_writeln_interleave;
{ Closing gate for feature-threadsafe-io-serialization AND the regression pin
  for bug-tthread-execute-writeln-crash: two TThreads each writeln 200
  60-char lines concurrently. Compiled with --threadsafe every output line
  must be atomic (the Makefile greps that every line is 60 As, 60 Bs, or done).
  Historically this program CRASHED before printing anything — the parser
  accepted `TW.Create` (missing the required CreateSuspended argument) and the
  ctor marshalling popped one register too many, desyncing the caller stack. }
uses palthreadobj;
type
  TW = class(TThread)
    ch: Char;
    procedure Execute; override;
  end;
procedure TW.Execute;
var i: Integer; s: AnsiString;
begin
  s := '';
  for i := 1 to 60 do s := s + ch;
  for i := 1 to 200 do writeln(s);
end;
var a, b: TW;
begin
  a := TW.Create(True); a.ch := 'A';
  b := TW.Create(True); b.ch := 'B';
  a.Start; b.Start;
  a.WaitFor; b.WaitFor;
  writeln('done');
end.
