{ SPDX-License-Identifier: Zlib }
unit subprocess;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `subprocess` for the Nil-Python frontend — the "launch a program"
  slice.

  Named `subprocess` so `import subprocess` needs no frontend change (NilPy maps
  `import X` onto the unit resolver; see devdocs/dev/python-compat-tiers.md).

  THE SUBSET, stated plainly:

    subprocess.Popen(argv_list, stdout=, stderr=, stdin=)  -> a Popen object
      with `.pid`, `.wait()`, `.poll()`, `.kill()`, `.terminate()`, and
      `.stdin` / `.stdout` for a PIPE. argv is a LIST, as in Python: the
      program is argv[0] and the rest are its arguments. No shell is involved,
      which matches `shell=False`, CPython's default and the safe one.
    subprocess.run(argv_list)     -> waits, and returns an object with
      `.returncode`.
    subprocess.call(argv_list)    -> the return code directly.
    subprocess.DEVNULL / PIPE / STDOUT — the constants, so a call that names
      them compiles and means what it says.
    stdin=PIPE / stdout=PIPE -> `p.stdin` / `p.stdout` are file objects on the
      parent's end of each pipe (write/flush/close, readline/read/close): a
      program driving a child line by line. They are unbuffered, so `bufsize=`
      is accepted and changes nothing. Without `text=True` the ends are
      binary (bytes), as in CPython. stdin=DEVNULL is honoured.
    cwd= on Popen and run(): the child starts in that directory.

  NOT here, and refused rather than approximated: `shell=True`, `stderr=PIPE` and
  `stderr=STDOUT`, `capture_output=`, `.communicate()`, `check=True`'s
  CalledProcessError, timeouts, env=. A redirection this unit cannot
  perform FAILS at the call rather than silently running the child with the
  parent's own stdout — the difference is visible on a terminal and invisible in
  a log, which is exactly the kind of thing a shim must not paper over.

  `stdout=DEVNULL` is honoured for real: the child is exec'd with /dev/null on
  its stdout. `stderr=DEVNULL` is ACCEPTED AND NOT HONOURED — the PAL's
  fork/exec entry wires stdin and stdout only, so the child's stderr is
  inherited. That is a visible, documented gap rather than a silent one (a
  viewer's chatter reaches the terminal); redirecting it needs a stderr fd in
  PalVforkAndExec, filed as feature-pal-spawn-stderr-redirect. }

interface

uses pylib, sysutils, platform;

const
  PIPE    = -1;
  STDOUT  = -2;
  DEVNULL = -3;

type
  Popen = class
  public
    pid: Integer;
    returncode: Integer;
    { the parent's ends of stdin=PIPE / stdout=PIPE; nil (None) otherwise }
    stdin: TPyFile;
    stdout: TPyFile;
    { `Popen(argv, stdout=, stderr=, stdin=, text=, bufsize=, cwd=)`. argv is
      a Python LIST. See the unit header for what is refused. }
    constructor Create(const argv: Variant; const stdout: Variant = 0;
                       const stderr: Variant = 0; const stdin: Variant = 0;
                       const text: Variant = 0; const bufsize: Variant = 0;
                       const cwd: Variant = 0);
    { Wait for the child and return its exit status, as CPython's does: the
      exit code, or minus the signal that ended it. }
    function wait: Integer;
    { The exit status if the child has finished, None if it is still running. }
    function poll: Variant;
    { SIGKILL / SIGTERM to the child; reaping it is still wait()'s job }
    procedure kill;
    procedure terminate;
  end;

{ `subprocess.run(argv)` — waits. The result carries `.returncode`, which is the
  attribute callers read. }
function run(const argv: Variant; const cwd: Variant = 0): Popen;
{ `subprocess.call(argv)` — waits and hands back the status. }
function call(const argv: Variant): Integer;

implementation

const
  O_CLOEXEC = 524288;   { 0o2000000; see Popen.Create }

{ The program to exec for argv[0], found the way execvp finds it, which is what
  CPython's Popen does: a name with a '/' is used as given, and a bare name is
  looked up in each PATH directory in order, the first executable one winning
  (an empty PATH entry is the current directory). With PATH unset the search
  list is glibc's default, /bin:/usr/bin. When nothing matches, the bare name is
  returned unchanged and the exec fails in the child as it did before (status
  127). Without this, `subprocess.run(["sh", "-c", "exit 3"])` answered 127:
  the exec below is execve, which never searches PATH. }
function ResolveProgram(const prog: AnsiString): AnsiString;
var path, dir, cand: AnsiString;
    i, start: Integer;
begin
  Result := prog;
  if (prog = '') or (Pos('/', prog) > 0) then Exit;
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
end;

{ argv[0] is the program; the rest are its arguments, which is Python's shape
  and ExecutePipeline's too. The program is resolved through PATH; argv[0]
  itself is passed on as written, as execvp does. }
function ArgvProgram(const argv: Variant): AnsiString;
var l: TPyList;
begin
  l := pylist_v(argv);
  if l.count < 1 then
  begin
    WriteLn('subprocess: the argument list is empty');
    Halt(1);
  end;
  Result := ResolveProgram(pystr_of(l.at(0)));
end;

procedure CheckRedirect(const v: Variant; const which: AnsiString; pipeOk: Boolean);
begin
  { Not given, or DEVNULL: those are the two this unit can honour. "Not given"
    is None (tag 0) or the 0 the parameter defaults to — the façade convention
    across lib/pcl and lib/rtl, and 0 is not a file descriptor any caller means
    here. Anything else would need the pipe surface this shim does not have. }
  if pyvartag(v) = 0 then Exit;
  if pyvar_to_int(v) = 0 then Exit;
  if pyvar_to_int(v) = DEVNULL then Exit;
  if pipeOk and (pyvar_to_int(v) = PIPE) then Exit;
  WriteLn('subprocess: ', which, '= is not supported yet (only PIPE, DEVNULL or omitted; ',
          'stderr takes DEVNULL or omitted)');
  Halt(1);
end;

function WantsDevNull(const v: Variant): Boolean;
begin
  Result := (pyvartag(v) <> 0) and (pyvar_to_int(v) = DEVNULL);
end;

function WantsPipe(const v: Variant): Boolean;
begin
  Result := (pyvartag(v) <> 0) and (pyvar_to_int(v) = PIPE);
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

constructor Popen.Create(const argv: Variant; const stdout, stderr, stdin,
                         text, bufsize, cwd: Variant);
var l: TPyList; i, devNull, devNullIn, res: Integer;
    inR, inW, outR, outW: Integer;
    pin, pout: array[0..1] of Integer;
    prog, dir, here: AnsiString;
    argvp: array of PChar;
    holds: array of AnsiString;      { keeps each argument alive across the exec }
    envp: Pointer;
begin
  CheckRedirect(stdout, 'stdout', True);
  CheckRedirect(stderr, 'stderr', False);
  CheckRedirect(stdin, 'stdin', True);
  Self.stdin := nil;
  Self.stdout := nil;
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
    the child ran with no PATH, HOME or LANG of its own. (Finding argv[0]
    itself is not the environment's job -- execve never searches PATH -- and
    ArgvProgram does that lookup in the parent.) }
  envp := EnvironmentBlock;
  { PalVforkAndExec dup2's the fds it is given and skips the ones that are -1,
    so /dev/null on the child's stdout is one open() away and everything else
    is inherited. ExecutePipeline is not used here: -1 asks IT to build pipes,
    and a spawned viewer's output would then go into a pipe nobody reads. }
  { The child dup2's the read end of its stdin and the write end of its
    stdout onto 0 and 1, and closes the other end of each. Pipes are made
    O_CLOEXEC so a LATER child does not inherit this one's ends -- otherwise
    the read side never sees EOF while that other child lives. }
  devNull := -1; devNullIn := -1;
  inR := -1; inW := -1; outR := -1; outW := -1;
  if WantsDevNull(stdout) then
  begin
    devNull := PalOpen(PChar('/dev/null'), 1, 0);   { O_WRONLY }
    outW := devNull;
  end
  else if WantsPipe(stdout) then
  begin
    if PalPipe2(pout, O_CLOEXEC) < 0 then
    begin
      WriteLn('subprocess: pipe() failed');
      Halt(1);
    end;
    outR := pout[0]; outW := pout[1];
  end;
  if WantsDevNull(stdin) then
  begin
    devNullIn := PalOpen(PChar('/dev/null'), 0, 0);   { O_RDONLY }
    inR := devNullIn;
  end
  else if WantsPipe(stdin) then
  begin
    if PalPipe2(pin, O_CLOEXEC) < 0 then
    begin
      WriteLn('subprocess: pipe() failed');
      Halt(1);
    end;
    inR := pin[0]; inW := pin[1];
  end;
  returncode := -1;
  { cwd=: the PAL's spawn has no chdir in the child, so the PARENT steps into
    the directory around the fork -- the child inherits it -- and steps back. }
  dir := CwdOf(cwd);
  here := '';
  if dir <> '' then
  begin
    here := GetCurrentDir;
    if PalChdir(PChar(dir)) < 0 then
    begin
      WriteLn('subprocess: cwd= ', dir, ': no such directory');
      Halt(1);
    end;
  end;
  pid := PalVforkAndExec(PChar(prog), @argvp[0], envp, inR, inW, outR, outW);
  if here <> '' then res := PalChdir(PChar(here));
  { the parent keeps only its own end of each pipe }
  if WantsPipe(stdout) then
  begin
    res := PalClose(outW);
    Self.stdout := PipeFile(outR, pyvar_to_bool(text));
  end;
  if WantsPipe(stdin) then
  begin
    res := PalClose(inR);
    Self.stdin := PipeFile(inW, pyvar_to_bool(text));
  end;
  if devNull >= 0 then res := PalClose(devNull);
  if devNullIn >= 0 then res := PalClose(devNullIn);
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

function run(const argv: Variant; const cwd: Variant): Popen;
var p: Popen;
begin
  { the three redirections passed EXPLICITLY: an omitted defaulted Variant
    parameter is bug-nilpy-omitted-variant-default-segfaults, and it bites in
    plain Pascal here too }
  p := Popen.Create(argv, 0, 0, 0, 0, 0, cwd);
  p.wait;
  Result := p;
end;

function call(const argv: Variant): Integer;
var p: Popen;
begin
  p := Popen.Create(argv, 0, 0, 0, 0, 0, 0);
  Result := p.wait;
end;

end.
