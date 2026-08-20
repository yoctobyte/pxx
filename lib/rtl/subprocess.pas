{ SPDX-License-Identifier: Zlib }
unit subprocess;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `subprocess` for the Nil-Python frontend — the "launch a program"
  slice.

  Named `subprocess` so `import subprocess` needs no frontend change (NilPy maps
  `import X` onto the unit resolver; see devdocs/dev/python-compat-tiers.md).

  THE SUBSET, stated plainly:

    subprocess.Popen(argv_list, stdout=, stderr=, stdin=)  -> a Popen object
      with `.pid`, `.wait()` and `.poll()`. argv is a LIST, as in Python: the
      program is argv[0] and the rest are its arguments. No shell is involved,
      which matches `shell=False`, CPython's default and the safe one.
    subprocess.run(argv_list)     -> waits, and returns an object with
      `.returncode`.
    subprocess.call(argv_list)    -> the return code directly.
    subprocess.DEVNULL / PIPE / STDOUT — the constants, so a call that names
      them compiles and means what it says.

  NOT here, and refused rather than approximated: `shell=True`, capturing output
  (`capture_output=`, `stdout=PIPE` then `.communicate()`), `check=True`'s
  CalledProcessError, timeouts, env=, cwd=. A redirection this unit cannot
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
    { `Popen(argv, stdout=..., stderr=..., stdin=...)`. argv is a Python LIST.
      A redirection other than DEVNULL (or omitted) is refused — see the unit
      header. }
    constructor Create(const argv: Variant; const stdout: Variant = 0;
                       const stderr: Variant = 0; const stdin: Variant = 0);
    { Wait for the child and return its exit status, as CPython's does. }
    function wait: Integer;
    { The exit status if the child has finished, None if it is still running. }
    function poll: Variant;
  end;

{ `subprocess.run(argv)` — waits. The result carries `.returncode`, which is the
  attribute callers read. }
function run(const argv: Variant): Popen;
{ `subprocess.call(argv)` — waits and hands back the status. }
function call(const argv: Variant): Integer;

implementation

{ argv[0] is the program; the rest are its arguments, which is Python's shape
  and ExecutePipeline's too. }
function ArgvProgram(const argv: Variant): AnsiString;
var l: TPyList;
begin
  l := pylist_v(argv);
  if l.count < 1 then
  begin
    WriteLn('subprocess: the argument list is empty');
    Halt(1);
  end;
  Result := pystr_of(l.at(0));
end;

procedure CheckRedirect(const v: Variant; const which: AnsiString);
begin
  { Not given, or DEVNULL: those are the two this unit can honour. "Not given"
    is None (tag 0) or the 0 the parameter defaults to — the façade convention
    across lib/pcl and lib/rtl, and 0 is not a file descriptor any caller means
    here. Anything else would need the pipe surface this shim does not have. }
  if pyvartag(v) = 0 then Exit;
  if pyvar_to_int(v) = 0 then Exit;
  if pyvar_to_int(v) = DEVNULL then Exit;
  WriteLn('subprocess: ', which, '= is not supported yet (only DEVNULL or omitted); ',
          'capturing a child''s output needs the pipe surface this shim does not have');
  Halt(1);
end;

function WantsDevNull(const v: Variant): Boolean;
begin
  Result := (pyvartag(v) <> 0) and (pyvar_to_int(v) = DEVNULL);
end;

constructor Popen.Create(const argv: Variant; const stdout, stderr, stdin: Variant);
var l: TPyList; i, devNull, res: Integer;
    prog: AnsiString;
    argvp: array of PChar;
    holds: array of AnsiString;      { keeps each argument alive across the exec }
    envp: Pointer;
begin
  CheckRedirect(stdout, 'stdout');
  CheckRedirect(stderr, 'stderr');
  CheckRedirect(stdin, 'stdin');
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
    no PATH, so `subprocess.run(["some_tool"])` could not even find its tool. }
  envp := EnvironmentBlock;
  { PalVforkAndExec dup2's the fds it is given and skips the ones that are -1,
    so /dev/null on the child's stdout is one open() away and everything else
    is inherited. ExecutePipeline is not used here: -1 asks IT to build pipes,
    and a spawned viewer's output would then go into a pipe nobody reads. }
  devNull := -1;
  if WantsDevNull(stdout) then devNull := PalOpen(PChar('/dev/null'), 1, 0);   { O_WRONLY }
  returncode := -1;
  pid := PalVforkAndExec(PChar(prog), @argvp[0], envp, -1, -1, -1, devNull);
  if devNull >= 0 then res := PalClose(devNull);
end;

function Popen.wait: Integer;
{ wait4 with no options: block until the child ends, then report the exit code
  the way a shell does (the status word's high byte). }
var status: Integer;
begin
  if pid > 0 then
  begin
    status := 0;
    if PalWait4(pid, @status, 0, nil) > 0 then
      returncode := (status shr 8) and 255;
  end;
  Result := returncode;
end;

function Popen.poll: Variant;
begin
  if returncode < 0 then Result := pynone else Result := returncode;
end;

function run(const argv: Variant): Popen;
var p: Popen;
begin
  { the three redirections passed EXPLICITLY: an omitted defaulted Variant
    parameter is bug-nilpy-omitted-variant-default-segfaults, and it bites in
    plain Pascal here too }
  p := Popen.Create(argv, 0, 0, 0);
  p.wait;
  Result := p;
end;

function call(const argv: Variant): Integer;
var p: Popen;
begin
  p := Popen.Create(argv, 0, 0, 0);
  Result := p.wait;
end;

end.
