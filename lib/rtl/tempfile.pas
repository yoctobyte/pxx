{ Python's `tempfile`, the slice real programs use.

  NilPy maps `import X` onto the Pascal unit resolver, so a unit NAMED for the
  module IS the module — see devdocs/dev/python-compat-tiers.md for why a shim is
  named after what it implements, and devdocs/legal/interface-compatibility.md
  for why that is legitimate.

  THE SUBSET, stated plainly, because a shim that quietly approximates is worse
  than one that refuses:

    tempfile.NamedTemporaryFile(suffix=, prefix=, dir=, delete=)   -> an object
      with `.name` and `.close()`.
    tempfile.gettempdir()          -> $TMPDIR, $TEMP, $TMP, /tmp, ... as CPython
    tempfile.mkdtemp(suffix=, prefix=, dir=)                        -> a path
    tempfile.mkstemp / TemporaryDirectory / SpooledTemporaryFile
      -> NOT here.

  THE DIFFERENCES FROM CPYTHON, all deliberate and all visible:

  1. The file is CREATED (empty) and immediately closed; the object is a NAME,
     not an open handle. CPython hands back a file object you can write through.
     Every censused use takes `.name` and hands it to something else that opens
     it by path, which is the shape this supports. Writing through the object is
     an error rather than a silent no-op — there is no write method to call.
  2. `delete=True` (CPython's default) removes the file at `.close()` and at
     the end of a `with` block, as CPython does. It is NOT removed when the
     object is merely dropped: a Pascal object's destructor does not run when
     NilPy releases it, so there is no collection hook. CPython also deletes
     then. So an unclosed delete=True file is left behind here. It used to raise
     at the call, which stopped every program that took the default.

  Defers to feature-nilpy-py-module-loader (T3): once the frontend can compile a
  package's own sources, the real tempfile compiles and this goes away. }
unit tempfile;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses sysutils, platform;   { platform: PalMkdir, for an exclusive 0700 create }

type
  NamedTemporaryFile = class
  public
    name: AnsiString;
    FDelete, FClosed: Boolean;
    constructor Create(const suffix: AnsiString = ''; const prefix: AnsiString = '';
                       const dir: AnsiString = ''; delete: Boolean = True);
    procedure close;
    function __enter__: NamedTemporaryFile;
    procedure __exit__(const a, b, c: Variant);
  end;

function gettempdir: AnsiString;

{ CPython's mkdtemp: create a directory nobody else can have, return its absolute
  path, and leave removing it to the caller. The two things worth stating because
  getting either wrong is silent:

  1. IT CREATES, EXCLUSIVELY. `mkdir` either makes the directory or fails; there
     is no exists-then-create window for a second process to win. A shim that
     built a random-looking name and handed it back WITHOUT creating it would pass
     every single-process test and race in production — which is the whole reason
     this is a real function and not a name generator.
  2. MODE 0700, in the mkdir call itself rather than a chmod afterwards, so the
     directory is never briefly group- or world-readable. CreateDir was not used
     for exactly that reason: it passes 0o777 and lets the umask decide, which
     measured 0o775 on this box -- group-WRITABLE as well as world-readable.

  Collisions retry on ANY mkdir failure rather than testing for EEXIST: this RTL
  has no EEXIST constant and the value is not the same across the posix, wasi and
  esp backends, so branching on a hard-coded number would be wrong somewhere. A
  genuine EACCES therefore costs TF_MKDTEMP_TRIES cheap failed syscalls before the
  raise, which is a fair price for not encoding a wrong errno. }
function mkdtemp(const suffix: AnsiString = ''; const prefix: AnsiString = '';
                 const dir: AnsiString = ''): AnsiString;

implementation

const
  { 0o700 and the retry bound. Written in decimal because {$MODE PXX} is not the
    place to rely on an octal literal spelling. }
  TF_MKDTEMP_MODE  = 448;
  TF_MKDTEMP_TRIES = 64;

{ A separate helper only because Pascal is CASE-INSENSITIVE: inside a function
  named `gettempdir`, the name `GetTempDir` IS this function, and a bare
  paramless own-name reads the RESULT variable instead of calling sysutils —
  which returned empty. Here the names differ, so the call is unambiguous. }
function TfSysTempDir: AnsiString;
begin
  TfSysTempDir := GetTempDir;
end;

var
  TfTempDir: AnsiString;   { CPython's tempfile.tempdir: fixed by the first call }

{ A candidate directory CPython would accept: it exists and we may create in
  it. CPython tests by creating a file; write+search access is the same answer
  without leaving anything behind. }
function TfUsableDir(const d: AnsiString): Boolean;
var z: AnsiString;
begin
  TfUsableDir := False;
  if d = '' then Exit;
  if not DirectoryExists(d) then Exit;
  z := d + #0;
  TfUsableDir := PalAccess(PChar(z), 3) = 0;    { W_OK or X_OK }
end;

{ os.path.abspath: absolute, no trailing separator (except the root). }
function TfAbs(const d: AnsiString): AnsiString;
var r: AnsiString;
begin
  if (Length(d) > 0) and (d[1] = '/') then r := d
  else r := GetCurrentDir + '/' + d;
  r := ExpandFileName(r);
  while (Length(r) > 1) and (r[Length(r)] = '/') do
    r := Copy(r, 1, Length(r) - 1);
  TfAbs := r;
end;

{ CPython's _candidate_tempdir_list order: $TMPDIR, $TEMP, $TMP, then /tmp,
  /var/tmp, /usr/tmp, then the current directory; the first usable one wins,
  and the answer is cached for the rest of the run. It used to be the RTL's
  fixed default temp directory, which ignored $TMPDIR. }
function gettempdir: AnsiString;
var d: AnsiString;
begin
  if TfTempDir = '' then
  begin
    d := '';
    if TfUsableDir(GetEnvironmentVariable('TMPDIR')) then d := GetEnvironmentVariable('TMPDIR')
    else if TfUsableDir(GetEnvironmentVariable('TEMP')) then d := GetEnvironmentVariable('TEMP')
    else if TfUsableDir(GetEnvironmentVariable('TMP')) then d := GetEnvironmentVariable('TMP')
    else if TfUsableDir('/tmp') then d := '/tmp'
    else if TfUsableDir('/var/tmp') then d := '/var/tmp'
    else if TfUsableDir('/usr/tmp') then d := '/usr/tmp'
    else d := GetCurrentDir;
    TfTempDir := TfAbs(d);
  end;
  gettempdir := TfTempDir;
end;

constructor NamedTemporaryFile.Create(const suffix, prefix, dir: AnsiString;
                                      delete: Boolean);
var base, pfx, d: AnsiString; f: TextFile;
begin
  FDelete := delete;
  FClosed := False;
  if prefix = '' then pfx := 'tmp' else pfx := prefix;
  if dir = '' then d := gettempdir else d := dir;
  base := GetTempFileName(d, pfx);
  name := base + suffix;
  { create it empty, so `.name` names a file that EXISTS — os.path.exists on it
    is true straight away, as it is in CPython }
  AssignFile(f, name);
  Rewrite(f);
  CloseFile(f);
end;

function mkdtemp(const suffix, prefix, dir: AnsiString): AnsiString;
var base, pfx, cand: AnsiString; n, i, rc: Integer;
begin
  if dir = '' then base := gettempdir else base := dir;
  if (Length(base) > 0) and (base[Length(base)] <> '/') then base := base + '/';
  if prefix = '' then pfx := 'tmp' else pfx := prefix;
  base := base + pfx;
  { seed from the monotonic clock so a restart does not retrace old names, the
    same reason GetTempFileName does it }
  n := Integer(PalMonotonicMillis mod 100000);
  for i := 1 to TF_MKDTEMP_TRIES do
  begin
    cand := base + IntToStr(n) + suffix;
    Inc(n);
    rc := PalMkdir(PChar(cand), TF_MKDTEMP_MODE);
    if rc = 0 then
    begin
      mkdtemp := cand;
      Exit;
    end;
  end;
  { Never hand back a path we did not create. }
  raise Exception.Create('tempfile.mkdtemp: could not create a unique directory '
    + 'under ' + base + ' after ' + IntToStr(TF_MKDTEMP_TRIES)
    + ' attempts (last mkdir rc=' + IntToStr(rc) + ')');
end;

procedure NamedTemporaryFile.close;
begin
  { Nothing is open (the object is a name, see the unit header). What close
    means here is CPython's delete=True: remove the file, once. }
  if FClosed then Exit;
  FClosed := True;
  if FDelete then DeleteFile(name);
end;

function NamedTemporaryFile.__enter__: NamedTemporaryFile;
begin
  __enter__ := Self;
end;

procedure NamedTemporaryFile.__exit__(const a, b, c: Variant);
begin
  close;
end;

end.
