{ Python's `tempfile`, the slice real programs use.

  NilPy maps `import X` onto the Pascal unit resolver, so a unit NAMED for the
  module IS the module — see devdocs/dev/python-compat-tiers.md for why a shim is
  named after what it implements, and devdocs/legal/interface-compatibility.md
  for why that is legitimate.

  THE SUBSET, stated plainly, because a shim that quietly approximates is worse
  than one that refuses:

    tempfile.NamedTemporaryFile(suffix=, prefix=, dir=, delete=)   -> an object
      with `.name` and `.close()`.
    tempfile.gettempdir()                                          -> '/tmp'
    tempfile.mkstemp / mkdtemp / TemporaryDirectory / SpooledTemporaryFile
      -> NOT here.

  TWO DIFFERENCES FROM CPYTHON, both deliberate and both visible:

  1. The file is CREATED (empty) and immediately closed; the object is a NAME,
     not an open handle. CPython hands back a file object you can write through.
     Every censused use takes `.name` and hands it to something else that opens
     it by path, which is the shape this supports. Writing through the object is
     an error rather than a silent no-op — there is no write method to call.
  2. `delete=True` is REFUSED, not honoured. CPython would remove the file when
     the object is closed or collected; NilPy has no finaliser to hang that on,
     and deleting at close would break the `.name`-then-open pattern above. So
     the honest answer is to fail at the call rather than delete at a moment the
     caller does not expect. `delete=False`, which is what the pattern uses, is
     the supported form.

  Defers to feature-nilpy-py-module-loader (T3): once the frontend can compile a
  package's own sources, the real tempfile compiles and this goes away. }
unit tempfile;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses sysutils;

type
  NamedTemporaryFile = class
  public
    name: AnsiString;
    constructor Create(const suffix: AnsiString = ''; const prefix: AnsiString = '';
                       const dir: AnsiString = ''; delete: Boolean = True);
    procedure close;
  end;

function gettempdir: AnsiString;

implementation

{ A separate helper only because Pascal is CASE-INSENSITIVE: inside a function
  named `gettempdir`, the name `GetTempDir` IS this function, and a bare
  paramless own-name reads the RESULT variable instead of calling sysutils —
  which returned empty. Here the names differ, so the call is unambiguous. }
function TfSysTempDir: AnsiString;
begin
  TfSysTempDir := GetTempDir;
end;

function gettempdir: AnsiString;
var d: AnsiString;
begin
  d := TfSysTempDir;
  { CPython's gettempdir() has no trailing separator; the RTL's has one }
  if (Length(d) > 1) and (d[Length(d)] = '/') then
    d := Copy(d, 1, Length(d) - 1);
  gettempdir := d;
end;

constructor NamedTemporaryFile.Create(const suffix, prefix, dir: AnsiString;
                                      delete: Boolean);
var base, pfx: AnsiString; f: TextFile;
begin
  if delete then
    raise Exception.Create('tempfile.NamedTemporaryFile(delete=True) is not '
      + 'supported: there is no finaliser to delete on, and deleting at close '
      + 'would break the .name-then-open pattern. Pass delete=False and remove '
      + 'the file yourself.');
  if prefix = '' then pfx := 'tmp' else pfx := prefix;
  base := GetTempFileName(dir, pfx);
  name := base + suffix;
  { create it empty, so `.name` names a file that EXISTS — os.path.exists on it
    is true straight away, as it is in CPython }
  AssignFile(f, name);
  Rewrite(f);
  CloseFile(f);
end;

procedure NamedTemporaryFile.close;
begin
  { the file is already closed — the object is a name, not a handle (see the
    unit header). Present so the call site's `.close()` compiles and means
    something honest: nothing is open. }
end;

end.
