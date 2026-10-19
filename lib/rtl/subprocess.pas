{ SPDX-License-Identifier: Zlib }
unit subprocess;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `subprocess` for the Nil-Python frontend — the "launch a program"
  slice.

  Named `subprocess` so `import subprocess` needs no frontend change (NilPy maps
  `import X` onto the unit resolver; see devdocs/dev/python-compat-tiers.md).

  THE SUBSET, stated plainly:

    subprocess.Popen(argv_list, stdout=, stderr=, stdin=, text=, cwd=)  -> a
      Popen object with `.pid`, `.args`, `.wait()`, `.poll()`, `.kill()`,
      `.terminate()`, `.communicate(timeout=)`, and `.stdin` / `.stdout` /
      `.stderr` for a PIPE. argv is a LIST, as in Python: the program is
      argv[0] and the rest are its arguments. No shell is involved, which
      matches `shell=False`, CPython's default and the safe one. A program
      that is not found raises FileNotFoundError, as CPython's Popen does.
    subprocess.run(argv_list, capture_output=, stdout=, stderr=, stdin=, text=,
      timeout=, check=, cwd=) -> waits, and returns a CompletedProcess with
      `.args`, `.returncode`, `.stdout`, `.stderr` and `.check_returncode()`.
      timeout= kills the child (SIGKILL) and raises TimeoutExpired, as CPython
      does; check=True raises CalledProcessError on a non-zero exit.
    subprocess.call(argv_list)    -> the return code directly.
    subprocess.DEVNULL / PIPE / STDOUT — the constants. stdout= takes PIPE or
      DEVNULL; stderr= takes PIPE, DEVNULL or STDOUT; stdin= takes PIPE or
      DEVNULL.
    stdin=PIPE / stdout=PIPE / stderr=PIPE -> file objects on the parent's end
      of each pipe (write/flush/close, readline/read/close): a program driving
      a child line by line. They are unbuffered, so `bufsize=` is accepted and
      changes nothing. Without `text=True` (or universal_newlines=True) they
      are binary (bytes), as in CPython; with it, captured output has its
      line endings translated to \n, as CPython's text mode does.
    SubprocessError, TimeoutExpired, CalledProcessError: CPython's hierarchy.

  NOT here, and refused rather than approximated: `shell=True`, env=, input=,
  wait(timeout=). A redirection this unit cannot perform FAILS at the call
  rather than silently running the child with the parent's own stdout -- the
  difference is visible on a terminal and invisible in a log, which is exactly
  the kind of thing a shim must not paper over. POSIX only: the ESP and wasi
  PALs have no process spawn. }

interface

uses sysutils, platform, pylib;

const
  PIPE    = -1;
  STDOUT  = -2;
  DEVNULL = -3;

type
  { CPython's hierarchy: SubprocessError(Exception), TimeoutExpired and
    CalledProcessError under it. Declared HERE, in the unit the program
    imports: NilPy registers the classes of that unit, and a class in a unit it
    merely uses is not found by `except subprocess.TimeoutExpired:` (measured).
    That is also why pylib comes LAST in the uses clause above: with sysutils
    last, a bare `Exception` is sysutils' class and str(e) renders as an object
    address instead of the message (mimic_sqlite3.pas, note 1). }
  SubprocessError = class(Exception) end;

  { run(timeout=) / communicate(timeout=) ran out of time. str(e) is CPython's
    sentence: "Command '[...]' timed out after 5 seconds". }
  TimeoutExpired = class(SubprocessError)
  public
    cmd: Variant;
    timeout: Variant;
    output: Variant;     { what was captured before the deadline, or None }
    stdout: Variant;     { the same value as output, as in CPython }
    stderr: Variant;
  end;

  { run(check=True) on a non-zero exit, and check_returncode().
    str(e): "Command '[...]' returned non-zero exit status 3." }
  CalledProcessError = class(SubprocessError)
  public
    returncode: Integer;
    cmd: Variant;
    output: Variant;
    stdout: Variant;
    stderr: Variant;
  end;

  Popen = class
  public
    pid: Integer;
    returncode: Integer;
    args: Variant;
    { the parent's ends of stdin=PIPE / stdout=PIPE / stderr=PIPE; nil (None)
      otherwise }
    stdin: TPyFile;
    stdout: TPyFile;
    stderr: TPyFile;
    FText: Boolean;
    { `Popen(argv, stdout=, stderr=, stdin=, text=, bufsize=, cwd=,
      universal_newlines=)`. argv is a Python LIST. See the unit header for
      what is refused. }
    constructor Create(const argv: Variant; const stdout: Variant = 0;
                       const stderr: Variant = 0; const stdin: Variant = 0;
                       const text: Variant = 0; const bufsize: Variant = 0;
                       const cwd: Variant = 0;
                       const universal_newlines: Variant = 0);
    { Wait for the child and return its exit status, as CPython's does: the
      exit code, or minus the signal that ended it. }
    function wait: Integer;
    { The exit status if the child has finished, None if it is still running. }
    function poll: Variant;
    { SIGKILL / SIGTERM to the child; reaping it is still wait()'s job }
    procedure kill;
    procedure terminate;
    { Read stdout and stderr (whichever are pipes) to their end, then wait for
      the child: (out, err), each None where that stream is not a pipe. Both
      pipes are drained TOGETHER, so a child that fills one while we read the
      other cannot deadlock. timeout= raises TimeoutExpired and leaves the child
      running, as CPython does; run() is the call that kills it. }
    function communicate(const timeout: Variant = 0): TPyList;
  end;

  CompletedProcess = class
  public
    args: Variant;
    returncode: Integer;
    stdout: Variant;
    stderr: Variant;
    { CalledProcessError if returncode is not 0 }
    procedure check_returncode;
  end;

{ `subprocess.run(argv, ...)` — waits, and hands back a CompletedProcess. cwd
  stays the second parameter because it was the only one before; CPython takes
  all of these by keyword. }
function run(const argv: Variant; const cwd: Variant = 0;
             const capture_output: Variant = 0; const stdout: Variant = 0;
             const stderr: Variant = 0; const stdin: Variant = 0;
             const text: Variant = 0; const timeout: Variant = 0;
             const check: Variant = 0;
             const universal_newlines: Variant = 0): CompletedProcess;
{ `subprocess.call(argv)` — waits and hands back the status. }
function call(const argv: Variant): Integer;

implementation

const
  O_CLOEXEC = 524288;   { 0o2000000; see Popen.Create }
  { STDOUT under a second name: Pascal is case-insensitive, so inside a routine
    with a `stdout` PARAMETER the bare constant is that parameter -- Popen.Create
    compared stderr against the caller's stdout argument and stderr=STDOUT
    silently merged nothing. }
  STDOUT_REDIRECT = STDOUT;
  POLLIN  = 1;
  POLLERR = 8;
  POLLHUP = 16;

type
  TPollFd = record
    fd: LongInt;
    events: SmallInt;
    revents: SmallInt;
  end;

{ The program to exec for argv[0], found the way execvp finds it, which is what
  CPython's Popen does: a name with a '/' is used as given, and a bare name is
  looked up in each PATH directory in order, the first executable one winning
  (an empty PATH entry is the current directory). With PATH unset the search
  list is glibc's default, /bin:/usr/bin. Without this,
  `subprocess.run(["sh", "-c", "exit 3"])` answered 127: the exec below is
  execve, which never searches PATH.

  Nothing found raises FileNotFoundError in the PARENT, before the fork, which
  is where CPython raises it ("[Errno 2] No such file or directory: 'x'"). It
  used to exec the bare name anyway and answer 127 from the child, so
  `except OSError` around a missing tool never ran (sysdash's nvidia-smi probe
  on a box without the tool). A path that exists but is not executable raises
  PermissionError, as CPython does. }
function ResolveProgram(const prog: AnsiString): AnsiString;
var path, dir, cand: AnsiString;
    i, start: Integer;
begin
  Result := prog;
  if prog = '' then pyos_raise_ioerror(2, prog, '');
  if Pos('/', prog) > 0 then
  begin
    if PalAccess(PChar(prog), 0) <> 0 then pyos_raise_ioerror(2, prog, '');   { F_OK }
    if PalAccess(PChar(prog), 1) <> 0 then pyos_raise_ioerror(13, prog, '');  { X_OK }
    Exit;
  end;
  path := GetEnvironmentVariable('PATH');
  if path = '' then path := '/bin:/usr/bin';
  start := 1;
  for i := 1 to Length(path) + 1 do
    if (i > Length(path)) or (path[i] = ':') then
    begin
      dir := Copy(path, start, i - start);
      start := i + 1;
      if dir = '' then cand := prog
      else cand := dir + '/' + prog;
      if PalAccess(PChar(cand), 1) = 0 then      { X_OK }
      begin
        Result := cand;
        Exit;
      end;
    end;
  pyos_raise_ioerror(2, prog, '');
end;

{ argv[0] is the program; the rest are its arguments, which is Python's shape
  and ExecutePipeline's too. The program is resolved through PATH; argv[0]
  itself is passed on as written, as execvp does. }
function ArgvProgram(const argv: Variant): AnsiString;
var l: TPyList;
begin
  l := pylist_v(argv);
  if l.count < 1 then
    raise IndexError.Create('subprocess: the argument list is empty');
  Result := ResolveProgram(pystr_of(l.at(0)));
end;

{ Not given is None (tag 0) or the 0 the parameter defaults to -- the facade
  convention across lib/pcl and lib/rtl, and 0 is not a file descriptor any
  caller means here. }
function Given(const v: Variant): Boolean;
begin
  Result := (pyvartag(v) <> 0) and (pyvar_to_int(v) <> 0);
end;

procedure CheckRedirect(const v: Variant; const which: AnsiString; stdoutOk: Boolean);
begin
  if not Given(v) then Exit;
  if pyvar_to_int(v) = DEVNULL then Exit;
  if pyvar_to_int(v) = PIPE then Exit;
  if stdoutOk and (pyvar_to_int(v) = STDOUT_REDIRECT) then Exit;
  raise ValueError.Create('subprocess: ' + which + '= takes PIPE, DEVNULL' +
                          ' (or STDOUT, for stderr) or nothing; a file object' +
                          ' or descriptor is not supported yet');
end;

function WantsDevNull(const v: Variant): Boolean;
begin
  Result := Given(v) and (pyvar_to_int(v) = DEVNULL);
end;

function WantsPipe(const v: Variant): Boolean;
begin
  Result := Given(v) and (pyvar_to_int(v) = PIPE);
end;

{ A file object on one end of a pipe. TPyFile's raw fd is unbuffered, which is
  what a line-by-line conversation with a child needs: a write is in the pipe
  when write() returns. BINARY unless text= (or universal_newlines=) asked for
  str, as in CPython: `p.stdout.readline()` is bytes by default. }
function PipeFile(fd: Integer; textMode: Boolean): TPyFile;
begin
  Result := TPyFile.Create;
  Result.FFd := fd;
  Result.FBinary := not textMode;
end;

{ cwd= : None / 0 / "" is "where we are". }
function CwdOf(const cwd: Variant): AnsiString;
begin
  Result := '';
  if pyvartag(cwd) <> 6 then Exit;
  Result := pystr_of(cwd);
end;

{ The status word as CPython reports it: the exit code, or MINUS the signal
  number for a child a signal ended (`p.kill(); p.wait()` is -9). }
function StatusCode(status: Integer): Integer;
begin
  if (status and $7F) <> 0 then Result := -(status and $7F)
  else Result := (status shr 8) and 255;
end;

function MakePipe(var r, w: Integer): Boolean;
var pp: array[0..1] of Integer;
begin
  Result := PalPipe2(pp, O_CLOEXEC) >= 0;
  if Result then begin r := pp[0]; w := pp[1]; end;
end;

constructor Popen.Create(const argv: Variant; const stdout, stderr, stdin,
                         text, bufsize, cwd, universal_newlines: Variant);
var l: TPyList; i, devNull, devNullIn, devNullErr, res: Integer;
    inR, inW, outR, outW, errR, errW: Integer;
    prog, dir, here: AnsiString;
    argvp: array of PChar;
    holds: array of AnsiString;      { keeps each argument alive across the exec }
    envp: Pointer;
begin
  CheckRedirect(stdout, 'stdout', False);
  CheckRedirect(stderr, 'stderr', True);
  CheckRedirect(stdin, 'stdin', False);
  Self.stdin := nil;
  Self.stdout := nil;
  Self.stderr := nil;
  Self.args := argv;
  FText := pyvar_to_bool(text) or pyvar_to_bool(universal_newlines);
  prog := ArgvProgram(argv);
  l := pylist_v(argv);
  { argv[0] is the program itself, as execve wants it, then the arguments,
    then the NULL terminator. }
  SetLength(holds, l.count);
  SetLength(argvp, l.count + 1);
  for i := 0 to l.count - 1 do
  begin
    holds[i] := pystr_of(l.at(i));
    argvp[i] := PChar(holds[i]);
  end;
  argvp[l.count] := nil;
  { The child inherits OUR environment — built in the parent, before vfork, so
    the first-use read of /proc/self/environ does not happen in the child. It
    used to be a hard-coded empty envp, which handed every subprocess `env -i`:
    the child ran with no PATH, HOME or LANG of its own. }
  envp := EnvironmentBlock;
  { PalVforkAndExec3 dup2's the fds it is given onto 0, 1 and 2 and skips the
    ones that are -1, which are inherited. Pipes are made O_CLOEXEC so a LATER
    child does not inherit this one's ends -- otherwise the read side never
    sees EOF while that other child lives. }
  devNull := -1; devNullIn := -1; devNullErr := -1;
  inR := -1; inW := -1; outR := -1; outW := -1; errR := -1; errW := -1;
  if WantsDevNull(stdout) then
  begin
    devNull := PalOpen(PChar('/dev/null'), 1, 0);   { O_WRONLY }
    outW := devNull;
  end
  else if WantsPipe(stdout) then
  begin
    if not MakePipe(outR, outW) then pyos_raise_oserror(24);
  end;
  if WantsDevNull(stderr) then
  begin
    devNullErr := PalOpen(PChar('/dev/null'), 1, 0);
    errW := devNullErr;
  end
  else if WantsPipe(stderr) then
  begin
    if not MakePipe(errR, errW) then pyos_raise_oserror(24);
  end
  else if Given(stderr) and (pyvar_to_int(stderr) = STDOUT_REDIRECT) then
    errW := -2;                                     { fd 2 := the child's fd 1 }
  if WantsDevNull(stdin) then
  begin
    devNullIn := PalOpen(PChar('/dev/null'), 0, 0);   { O_RDONLY }
    inR := devNullIn;
  end
  else if WantsPipe(stdin) then
  begin
    if not MakePipe(inR, inW) then pyos_raise_oserror(24);
  end;
  returncode := -1;
  { cwd=: the PAL's spawn has no chdir in the child, so the PARENT steps into
    the directory around the fork -- the child inherits it -- and steps back. }
  dir := CwdOf(cwd);
  here := '';
  if dir <> '' then
  begin
    here := GetCurrentDir;
    if PalChdir(PChar(dir)) < 0 then pyos_raise_ioerror(2, dir, '');
  end;
  pid := PalVforkAndExec3(PChar(prog), @argvp[0], envp, inR, inW, outR, outW, errR, errW);
  if here <> '' then res := PalChdir(PChar(here));
  { the parent keeps only its own end of each pipe }
  if WantsPipe(stdout) then
  begin
    res := PalClose(outW);
    Self.stdout := PipeFile(outR, FText);
  end;
  if WantsPipe(stderr) then
  begin
    res := PalClose(errW);
    Self.stderr := PipeFile(errR, FText);
  end;
  if WantsPipe(stdin) then
  begin
    res := PalClose(inR);
    Self.stdin := PipeFile(inW, FText);
  end;
  if devNull >= 0 then res := PalClose(devNull);
  if devNullErr >= 0 then res := PalClose(devNullErr);
  if devNullIn >= 0 then res := PalClose(devNullIn);
  if pid < 0 then pyos_raise_oserror(-pid);
end;

procedure Popen.kill;
var r: Integer;
begin
  if (pid > 0) and (returncode = -1) then r := PalKill(pid, 9);
end;

procedure Popen.terminate;
var r: Integer;
begin
  if (pid > 0) and (returncode = -1) then r := PalKill(pid, 15);
end;

function Popen.wait: Integer;
{ wait4 with no options: block until the child ends. }
var status: Integer;
begin
  if (pid > 0) and (returncode = -1) then
  begin
    status := 0;
    if PalWait4(pid, @status, 0, nil) > 0 then
      returncode := StatusCode(status);
  end;
  Result := returncode;
end;

{ The exit status if the child has finished, None if it is still running --
  asked of the kernel (WNOHANG), as CPython's poll() does, rather than
  answering from whatever wait() last recorded. }
function Popen.poll: Variant;
var status: Integer;
begin
  if (pid > 0) and (returncode = -1) then
  begin
    status := 0;
    if PalWait4(pid, @status, 1, nil) > 0 then    { WNOHANG }
      returncode := StatusCode(status);
  end;
  if returncode = -1 then Result := pynone else Result := returncode;
end;

{ CPython's text mode reads with universal newlines: \r\n and a lone \r both
  arrive as \n. }
function TranslateNewlines(const s: AnsiString): AnsiString;
var i, n: Integer;
begin
  if Pos(#13, s) = 0 then begin Result := s; Exit; end;
  SetLength(Result, Length(s));
  n := 0;
  i := 1;
  while i <= Length(s) do
  begin
    Inc(n);
    if s[i] = #13 then
    begin
      Result[n] := #10;
      if (i < Length(s)) and (s[i + 1] = #10) then Inc(i);
    end
    else
      Result[n] := s[i];
    Inc(i);
  end;
  SetLength(Result, n);
end;

{ A captured stream as Python sees it: str in text mode, bytes otherwise. }
function Captured(const s: AnsiString; textMode: Boolean): Variant;
begin
  if textMode then Result := TranslateNewlines(s)
  else Result := bytes(s);
end;

{ The deadline for a timeout= value, as PalMonotonicMillis; -1 for none. }
function DeadlineOf(const timeout: Variant): Int64;
begin
  Result := -1;
  if pyvartag(timeout) = 0 then Exit;
  Result := PalMonotonicMillis + Round(pyvar_to_float(timeout) * 1000.0);
end;

{ Milliseconds left before the deadline, for a poll(): -1 waits forever. }
function MillisLeft(deadline: Int64): Integer;
var left: Int64;
begin
  if deadline < 0 then begin Result := -1; Exit; end;
  left := deadline - PalMonotonicMillis;
  if left < 0 then left := 0;
  if left > 1000000000 then left := 1000000000;
  Result := Integer(left);
end;

{ The captured output rides on the exception as BYTES even under text=True:
  CPython documents that, because a deadline can cut a multi-byte character in
  half. }
procedure RaiseTimeout(const cmd, timeout: Variant; const outS, errS: AnsiString;
                       outPiped, errPiped: Boolean);
var e: TimeoutExpired;
begin
  e := TimeoutExpired.Create('Command ''' + pyvar_repr(cmd) + ''' timed out after ' +
                             pystr_of(timeout) + ' seconds');
  e.cmd := cmd;
  e.timeout := timeout;
  if outPiped then e.output := bytes(outS) else e.output := pynone;
  e.stdout := e.output;
  if errPiped then e.stderr := bytes(errS) else e.stderr := pynone;
  raise e;
end;

{ Drain whichever of stdout/stderr are pipes until both reach EOF or the
  deadline passes. Both are polled as ONE set, which is what keeps a child
  that writes a lot to stderr from blocking while we wait on stdout. Answers
  False on the deadline. }
function Drain(p: Popen; deadline: Int64; var outS, errS: AnsiString): Boolean;
var fds: array[0..1] of TPollFd;
    which: array[0..1] of Integer;   { 0 = stdout, 1 = stderr }
    buf: array[0..16383] of Byte;
    nf, k, r, old: Integer;
    n: Int64;
    f: TPyFile;
begin
  Result := True;
  while True do
  begin
    nf := 0;
    if (p.stdout <> nil) and (p.stdout.FFd >= 0) then
    begin
      fds[nf].fd := p.stdout.FFd; fds[nf].events := POLLIN; fds[nf].revents := 0;
      which[nf] := 0; Inc(nf);
    end;
    if (p.stderr <> nil) and (p.stderr.FFd >= 0) then
    begin
      fds[nf].fd := p.stderr.FFd; fds[nf].events := POLLIN; fds[nf].revents := 0;
      which[nf] := 1; Inc(nf);
    end;
    if nf = 0 then Exit;
    r := PalPollSet(@fds[0], nf, MillisLeft(deadline));
    if r = -4 then Continue;                      { EINTR }
    if r = 0 then begin Result := False; Exit; end;
    if r < 0 then pyos_raise_oserror(-r);
    for k := 0 to nf - 1 do
      if (fds[k].revents and (POLLIN or POLLHUP or POLLERR)) <> 0 then
      begin
        if which[k] = 0 then f := p.stdout else f := p.stderr;
        n := PalRead(fds[k].fd, @buf[0], SizeOf(buf));
        if n = -4 then Continue;                  { EINTR }
        if n <= 0 then
          f.close                                 { EOF: FFd goes to -1 }
        else if which[k] = 0 then
        begin
          old := Length(outS);
          SetLength(outS, old + Integer(n));
          Move(buf[0], outS[old + 1], n);
        end
        else
        begin
          old := Length(errS);
          SetLength(errS, old + Integer(n));
          Move(buf[0], errS[old + 1], n);
        end;
      end;
  end;
end;

{ Reap the child by the deadline: WNOHANG polls 10 ms apart, since there is
  no wait-with-timeout syscall. Without a deadline, a plain blocking wait. }
function ReapBy(p: Popen; deadline: Int64): Boolean;
var r: Integer;
begin
  Result := True;
  if deadline < 0 then begin p.wait; Exit; end;
  while pyvartag(p.poll) = 0 do
  begin
    if MillisLeft(deadline) <= 0 then begin Result := False; Exit; end;
    r := PalNanosleep(0, 10000000);
  end;
end;

function Popen.communicate(const timeout: Variant): TPyList;
var outS, errS: AnsiString; deadline: Int64; l: TPyList; v: Variant; res: Integer;
begin
  outS := ''; errS := '';
  deadline := DeadlineOf(timeout);
  if stdin <> nil then stdin.close;   { no input=: the child sees EOF at once }
  if not Drain(Self, deadline, outS, errS) then
    RaiseTimeout(args, timeout, outS, errS, stdout <> nil, stderr <> nil);
  if not ReapBy(Self, deadline) then
    RaiseTimeout(args, timeout, outS, errS, stdout <> nil, stderr <> nil);
  l := TPyList.Create;
  if stdout <> nil then v := Captured(outS, FText) else v := pynone;
  l.append(v);
  if stderr <> nil then v := Captured(errS, FText) else v := pynone;
  l.append(v);
  Result := pylist_mark_tuple(l);
end;

procedure RaiseCalled(code: Integer; const cmd, outV, errV: Variant);
var e: CalledProcessError;
begin
  if code < 0 then
    e := CalledProcessError.Create('Command ''' + pyvar_repr(cmd) + ''' died with signal ' +
                                   IntToStr(-code) + '.')
  else
    e := CalledProcessError.Create('Command ''' + pyvar_repr(cmd) +
                                   ''' returned non-zero exit status ' + IntToStr(code) + '.');
  e.returncode := code;
  e.cmd := cmd;
  e.output := outV;
  e.stdout := outV;
  e.stderr := errV;
  raise e;
end;

procedure CompletedProcess.check_returncode;
begin
  if returncode <> 0 then RaiseCalled(returncode, args, stdout, stderr);
end;

function run(const argv: Variant; const cwd: Variant;
             const capture_output: Variant; const stdout: Variant;
             const stderr: Variant; const stdin: Variant;
             const text: Variant; const timeout: Variant;
             const check: Variant;
             const universal_newlines: Variant): CompletedProcess;
var p: Popen; o, e: Variant; cp: CompletedProcess;
    outS, errS: AnsiString; deadline: Int64; res: Integer;
begin
  o := stdout; e := stderr;
  if pyvar_to_bool(capture_output) then
  begin
    if Given(stdout) or Given(stderr) then
      raise ValueError.Create('stdout and stderr arguments may not be used with capture_output.');
    o := PIPE; e := PIPE;
  end;
  { every parameter passed EXPLICITLY: an omitted defaulted Variant parameter
    is bug-nilpy-omitted-variant-default-segfaults, and it bites in plain
    Pascal here too }
  p := Popen.Create(argv, o, e, stdin, text, 0, cwd, universal_newlines);
  deadline := DeadlineOf(timeout);
  outS := ''; errS := '';
  if p.stdin <> nil then p.stdin.close;
  if (not Drain(p, deadline, outS, errS)) or (not ReapBy(p, deadline)) then
  begin
    { CPython's run(): kill the child, reap it, then raise }
    p.kill;
    p.wait;
    if p.stdout <> nil then p.stdout.close;
    if p.stderr <> nil then p.stderr.close;
    RaiseTimeout(argv, timeout, outS, errS, p.stdout <> nil, p.stderr <> nil);
  end;
  cp := CompletedProcess.Create;
  cp.args := argv;
  cp.returncode := p.returncode;
  if p.stdout <> nil then cp.stdout := Captured(outS, p.FText) else cp.stdout := pynone;
  if p.stderr <> nil then cp.stderr := Captured(errS, p.FText) else cp.stderr := pynone;
  if pyvar_to_bool(check) then cp.check_returncode;
  Result := cp;
end;

function call(const argv: Variant): Integer;
var p: Popen;
begin
  p := Popen.Create(argv, 0, 0, 0, 0, 0, 0, 0);
  Result := p.wait;
end;

end.
