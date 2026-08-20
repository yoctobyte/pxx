{ Python's `pathlib`, the slice real programs use.

  NilPy maps `import X` onto the Pascal unit resolver, so a unit NAMED for the
  module IS the module — see devdocs/dev/python-compat-tiers.md.

  THE SUBSET:
    Path(s)                     .name .stem .suffix .parent
    p / 'child'                 join, Python's own spelling
    p.exists() .is_file() .is_dir()
    p.mkdir(parents=, exist_ok=)
    p.open(mode, encoding=)     -> a file object with read/write/close, the
                                   shape `with p.open(...) as f` needs
    p.read_text() .write_text()
    str(p)                      -> the path text
  Not here: glob, rglob, resolve, absolute, PurePath, Windows flavours, or the
  comparison/hash protocol. Anything outside the subset is a compile error at the
  use site rather than a silent approximation.

  Defers to feature-nilpy-py-module-loader (T3). }
unit pathlib;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

{ pylib FIRST: both it and sysutils declare `Exception`, the name is shared
  program-wide, and the first unit to register it owns the row — with sysutils
  first, pylib's own method bodies bind to sysutils' class and the unit fails
  to compile ("undefined variable (msg)"). Same reason as lib/rtl/json.pas;
  see decide-class-namespace-scoping. }
uses pylib, sysutils, platform;   { Path.open hands back pylib's file object }

type
  Path = class
  public
    s: AnsiString;               { the path text — `str(p)` reads this }
    constructor Create(const value: AnsiString);
    { name / stem / suffix / parent are PROPERTIES in Python — written without
      parentheses — so they are properties here too. As plain functions the
      no-parens read yielded nothing at all. }
    function GetName: AnsiString;
    function GetStem: AnsiString;
    function GetSuffix: AnsiString;
    function GetParent: Path;
    property name: AnsiString read GetName;
    property stem: AnsiString read GetStem;
    property suffix: AnsiString read GetSuffix;
    property parent: Path read GetParent;
    function exists: Boolean;
    function is_file: Boolean;
    function is_dir: Boolean;
    procedure mkdir(parents: Boolean = False; exist_ok: Boolean = False);
    function joinpath(const child: AnsiString): Path;
    { `p.with_suffix(".pdf")` — the same path with its extension replaced (or
      added when there is none), and `.with_name(...)` beside it. CPython
      requires the new suffix to start with a dot, or be empty to strip. }
    function with_suffix(const suffix: AnsiString): Path;
    function with_name(const name: AnsiString): Path;
    { Python renders a Path through __str__; NilPy calls it for `str(p)` and
      `print(p)` the same way (feature-nilpy-dunder-str). Without one, a class
      printed its instance POINTER. }
    function __str__: AnsiString;
    function read_text: AnsiString;
    procedure write_text(const data: AnsiString);
    { `with p.open("w", encoding="utf-8") as f:` — the file object is pylib's
      TPyFile, the same one the builtin `open(path, mode)` yields for a write
      mode, so json.dump and f.write take it unchanged. `encoding` and the
      other text-mode options are accepted and ignored: our strings are byte
      strings, so there is no decode step to configure. }
    function open(const mode: AnsiString = 'r'; const encoding: AnsiString = '';
                  const errors: AnsiString = '';
                  const newline: AnsiString = ''): TPyFile;
  end;

{ mkdir goes straight to the platform layer: the RTL has DirectoryExists but no
  CreateDir, and PalMkdir is what pxxcio uses for the same job. 0o755 is
  CPython's own default mode for Path.mkdir. }
{ `p / 'child'`, which is how pathlib is written. }
operator / (a: Path; b: AnsiString): Path;

implementation

function PlJoin(const a, b: AnsiString): AnsiString;
begin
  if a = '' then PlJoin := b
  else if (Length(a) > 0) and (a[Length(a)] = '/') then PlJoin := a + b
  else PlJoin := a + '/' + b;
end;

constructor Path.Create(const value: AnsiString);
begin
  s := value;
end;

function Path.GetName: AnsiString;
var i, cut: Integer;
begin
  cut := 0;
  for i := 1 to Length(s) do
    if s[i] = '/' then cut := i;
  GetName := Copy(s, cut + 1, Length(s) - cut);
end;

function Path.GetSuffix: AnsiString;
var i, dot: Integer; base: AnsiString;
begin
  base := GetName;
  dot := 0;
  for i := 1 to Length(base) do
    if base[i] = '.' then dot := i;
  { a leading dot is a hidden file, not a suffix — CPython agrees }
  if dot <= 1 then GetSuffix := '' else GetSuffix := Copy(base, dot, Length(base) - dot + 1);
end;

function Path.GetStem: AnsiString;
var base: AnsiString;
begin
  base := GetName;
  GetStem := Copy(base, 1, Length(base) - Length(GetSuffix));
end;

function Path.GetParent: Path;
var i, cut: Integer;
begin
  cut := 0;
  for i := 1 to Length(s) do
    if s[i] = '/' then cut := i;
  if cut = 0 then GetParent := Path.Create('.')
  else if cut = 1 then GetParent := Path.Create('/')
  else GetParent := Path.Create(Copy(s, 1, cut - 1));
end;

function Path.exists: Boolean;
begin
  exists := FileExists(s) or DirectoryExists(s);
end;

function Path.is_file: Boolean;
begin
  is_file := FileExists(s);
end;

function Path.is_dir: Boolean;
begin
  is_dir := DirectoryExists(s);
end;

procedure Path.mkdir(parents: Boolean; exist_ok: Boolean);
var i: Integer; part: AnsiString;
begin
  if DirectoryExists(s) then
  begin
    { CPython raises FileExistsError unless exist_ok — say so rather than
      pretending the call did something }
    if not exist_ok then
      raise Exception.Create('FileExistsError: ' + s);
    Exit;
  end;
  if parents then
  begin
    part := '';
    for i := 1 to Length(s) do
    begin
      if (s[i] = '/') and (part <> '') and (not DirectoryExists(part)) then
        PalMkdir(PChar(part), 493);   { 493 = 0o755 }
      part := part + s[i];
    end;
  end;
  PalMkdir(PChar(s), 493);
end;

function Path.joinpath(const child: AnsiString): Path;
begin
  joinpath := Path.Create(PlJoin(s, child));
end;

function Path.with_suffix(const suffix: AnsiString): Path;
var i, cut, lastSlash: Integer; base: AnsiString;
begin
  lastSlash := 0;
  cut := 0;
  for i := 1 to Length(s) do
  begin
    if (s[i] = '/') then begin lastSlash := i; cut := 0; end;
    if (s[i] = '.') and (i > lastSlash + 1) then cut := i;
  end;
  if cut > 0 then
  begin
    base := '';
    for i := 1 to cut - 1 do base := base + s[i];
  end
  else
    base := s;
  with_suffix := Path.Create(base + suffix);
end;

function Path.with_name(const name: AnsiString): Path;
var i, lastSlash: Integer; dir: AnsiString;
begin
  lastSlash := 0;
  for i := 1 to Length(s) do
    if s[i] = '/' then lastSlash := i;
  dir := '';
  for i := 1 to lastSlash do dir := dir + s[i];
  with_name := Path.Create(dir + name);
end;

function Path.__str__: AnsiString;
begin
  __str__ := s;
end;

function Path.read_text: AnsiString;
var f: TextFile; line, r: AnsiString; first: Boolean;
begin
  r := '';
  first := True;
  AssignFile(f, s);
  Reset(f);
  while not Eof(f) do
  begin
    ReadLn(f, line);
    if not first then r := r + #10;
    r := r + line;
    first := False;
  end;
  CloseFile(f);
  read_text := r;
end;

procedure Path.write_text(const data: AnsiString);
var f: TextFile;
begin
  AssignFile(f, s);
  Rewrite(f);
  Write(f, data);
  CloseFile(f);
end;

operator / (a: Path; b: AnsiString): Path;
begin
  Result := Path.Create(PlJoin(a.s, b));
end;


function Path.open(const mode, encoding, errors, newline: AnsiString): TPyFile;
begin
  open := pyfile_open(Self.s, mode);
end;

end.
