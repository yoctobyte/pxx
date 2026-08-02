{ A spawned child inherits the parent's environment.

  Every spawn site used to hard-code an empty envp, so a pxx-compiled program
  handed each child the equivalent of `env -i` — no PATH, no HOME, no TZ — even
  when the program never touched the environment itself. Nothing errored: the
  child simply behaved as if started with nothing, so a tool invoked by name
  could not be found and every $VAR it read was empty.

  The variables checked here are ones this program never sets — they come from
  the environment the TEST RUNNER was started with, which is the whole point:
  the bug was that an unmodified environment did not reach the child either.
  HOME and PATH are used because a test runner without them is not a scenario
  worth guarding against.

  HOME is the load-bearing check, and PATH is NOT — verified by rebuilding
  against the pre-fix RTL and watching which assertions fail. With an empty
  envp, `test -n "$PATH"` still SUCCEEDS, because /bin/sh synthesises a default
  PATH when it inherits none. A test that only looked at PATH would have passed
  against the bug. HOME has no such fallback, and comparing it to the parent's
  actual value is stronger again. }
program lib_child_env;
uses sysutils, textfile;

var fails: Integer;

procedure Chk(const what: AnsiString; got, want: Boolean);
begin
  if got = want then WriteLn(what, '=ok')
  else begin WriteLn(what, ' FAIL got=', got, ' want=', want); fails := fails + 1; end;
end;

{ Run a /bin/sh test expression in a child and report whether it succeeded.
  The child's exit status is the answer, so nothing has to be read back. }
function ChildSucceeds(const shellExpr: AnsiString): Boolean;
var inFd, outFd, pid, status, n: Integer; buf: array[0..255] of Char;
begin
  inFd := -1; outFd := -1;
  pid := ExecutePipeline('/bin/sh', ['-c', shellExpr], inFd, outFd);
  if pid < 0 then begin ChildSucceeds := False; Exit; end;
  if inFd >= 0 then n := PalClose(inFd);
  { drain, so the child never blocks writing, then reap it }
  if outFd >= 0 then
  begin
    repeat n := PalRead(outFd, @buf[0], SizeOf(buf)); until n <= 0;
    n := PalClose(outFd);
  end;
  status := 0;
  if PalWait4(pid, @status, 0, nil) > 0 then
    ChildSucceeds := ((status shr 8) and 255) = 0
  else
    ChildSucceeds := False;
end;

begin
  fails := 0;

  { the parent can see them — if not, the runner's own environment is the
    problem and the child checks below would be meaningless }
  Chk('parent_home', GetEnvironmentVariable('HOME') <> '', True);
  Chk('parent_path', GetEnvironmentVariable('PATH') <> '', True);

  { the child sees them too. This is the regression: it used to be False. }
  Chk('child_home',  ChildSucceeds('test -n "$HOME"'), True);
  Chk('child_path',  ChildSucceeds('test -n "$PATH"'), True);

  { the child's HOME is the SAME value, not merely some value }
  Chk('child_home_matches',
      ChildSucceeds('test "$HOME" = "' + GetEnvironmentVariable('HOME') + '"'), True);

  { a variable nobody set is still unset in the child — the envp is the
    parent's environment, not a wildcard that makes every test pass }
  Chk('child_unset',
      ChildSucceeds('test -z "$PXX_DEFINITELY_NOT_SET_ANYWHERE"'), True);

  if fails = 0 then WriteLn('CHILDENV OK')
  else WriteLn('CHILDENV FAILED ', fails);
end.
