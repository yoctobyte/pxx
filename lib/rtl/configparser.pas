{ SPDX-License-Identifier: Zlib }
unit configparser;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `configparser` for the Nil-Python frontend.

  Named `configparser` on purpose, like lib/rtl/re.pas: NilPy turns `import X`
  into the Pascal unit resolver's `uses X`, so the unit name IS the module name
  and both `configparser.ConfigParser()` and a bare `ConfigParser()` resolve.

  Deliberately depends on NOTHING — not even sysutils. A `.npy` program pulls
  pylib's Python-shaped `Exception`, which shadows sysutils' identical
  declaration, so any unit reaching sysutils currently fails on
  `Exception.CreateFmt` (bug-nilpy-rtl-exception-surface-shadowed). Staying
  self-contained sidesteps that entirely, and an INI reader needs nothing more
  than string slicing anyway.

  `optionxform` is VIRTUAL because that is the whole reason real code subclasses
  ConfigParser:

      class CasePreservingConfigParser(configparser.ConfigParser):
          def optionxform(self, optionstr):
              return optionstr

  Python methods are always virtual; Pascal's are not, so without `virtual` the
  override would compile and silently never run.

  Differences from CPython, all deliberate:
  * No interpolation (`%(name)s` in values is returned verbatim). CPython's
    BasicInterpolation is a separate layer and no consumer here uses it.
  * `get` raises nothing: a missing section or option returns ''. Callers here
    guard with has_section/has_option, and NilPy cannot yet catch a raise from
    library code anyway (feature-nilpy-catchable-runtime-errors).
  * Sections and options keep INSERTION order, which is what a settings file
    round-trip wants. }

interface

{ pylib for TPyFile: `cfg.write(f)` hands over NilPy's file object, and a
  configparser that cannot take it forces the application to change — which the
  compile-as-is mission rules out (see decide-pcl-may-use-pylib for the same
  call in the tkinter façade). }
uses pylib;

const
  CP_MAX_SECTIONS = 64;
  CP_MAX_OPTIONS  = 256;   { per section }

type
  TCpSection = record
    name: AnsiString;
    keys: array[0..CP_MAX_OPTIONS - 1] of AnsiString;
    vals: array[0..CP_MAX_OPTIONS - 1] of AnsiString;
    count: Integer;
  end;

  ConfigParser = class
  public
    sects: array[0..CP_MAX_SECTIONS - 1] of TCpSection;
    nsect: Integer;
    constructor Create;

    { CPython lowercases option names; override this to keep their case. }
    function optionxform(const s: AnsiString): AnsiString; virtual;

    function has_section(const section: AnsiString): Boolean;
    procedure add_section(const section: AnsiString);
    function has_option(const section, option: AnsiString): Boolean;
    function get(const section, option: AnsiString): AnsiString;
    procedure set(const section, option, value: AnsiString);
    { CPython returns a LIST of section names, and applications iterate it
      (`for s in cfg.sections()`); the newline-joined string made that iterate
      CHARACTERS. sections_text keeps the old spelling for Pascal callers. }
    function sections: TPyList;
    function sections_text: AnsiString;  { newline-separated, see section_count }
    { CPython's items(section): the (key, value) pairs of one section, which is
      how a settings UI walks it. Each pair is a 2-element list — NilPy's tuple. }
    function items(const section: AnsiString): TPyList;
    { options(section): just the names }
    function options(const section: AnsiString): TPyList;
    function section_count: Integer;
    function section_at(i: Integer): AnsiString;
    function option_count(const section: AnsiString): Integer;
    function option_at(const section: AnsiString; i: Integer): AnsiString;
    function value_at(const section: AnsiString; i: Integer): AnsiString;

    { read(path) / write(path): the file forms. CPython's write takes an open
      file object; a path keeps this unit free of a file-object dependency, and
      the caller has the path. }
    function read(const path: AnsiString): Boolean;
    function write(const path: AnsiString): Boolean;
    { CPython's spelling: `cfg.write(f)` with an OPEN FILE, which is what
      applications write (songformatter's settings module does). The file object
      is NilPy's TPyFile; its fd takes the text directly. }
    function write(f: TPyFile): Boolean; overload;

    { Parse from a string, so a caller can supply the text however it likes. }
    procedure take_line(const raw: AnsiString; var cur: AnsiString);
    procedure read_string(const text: AnsiString);
    function to_string: AnsiString;
  end;

implementation

function CpLower(const s: AnsiString): AnsiString;
var i: Integer; r: AnsiString;
begin
  r := s;
  for i := 1 to Length(r) do
    if (r[i] >= 'A') and (r[i] <= 'Z') then r[i] := Chr(Ord(r[i]) + 32);
  CpLower := r;
end;

function CpTrim(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1;
  b := Length(s);
  while (a <= b) and ((s[a] = ' ') or (s[a] = #9) or (s[a] = #13)) do a := a + 1;
  while (b >= a) and ((s[b] = ' ') or (s[b] = #9) or (s[b] = #13)) do b := b - 1;
  if b < a then CpTrim := '' else CpTrim := Copy(s, a, b - a + 1);
end;

constructor ConfigParser.Create;
begin
  nsect := 0;
end;

function ConfigParser.optionxform(const s: AnsiString): AnsiString;
begin
  optionxform := CpLower(s);
end;

function ConfigParser.has_section(const section: AnsiString): Boolean;
var i: Integer; hit: Boolean;
begin
  hit := False;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then hit := True;
  has_section := hit;
end;

procedure ConfigParser.add_section(const section: AnsiString);
begin
  if has_section(section) then exit;
  if nsect >= CP_MAX_SECTIONS then exit;
  sects[nsect].name := section;
  sects[nsect].count := 0;
  nsect := nsect + 1;
end;

function ConfigParser.has_option(const section, option: AnsiString): Boolean;
var i, j: Integer; key: AnsiString; hit: Boolean;
begin
  key := optionxform(option);
  hit := False;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then
      for j := 0 to sects[i].count - 1 do
        if sects[i].keys[j] = key then hit := True;
  has_option := hit;
end;

function ConfigParser.get(const section, option: AnsiString): AnsiString;
var i, j: Integer; key, res: AnsiString;
begin
  key := optionxform(option);
  res := '';
  for i := 0 to nsect - 1 do
    if sects[i].name = section then
      for j := 0 to sects[i].count - 1 do
        if sects[i].keys[j] = key then res := sects[i].vals[j];
  get := res;
end;

{ CPython's own spelling. `set` is a type keyword in Pascal, but PXX parses a
  member name contextually, so the API can carry the name the application
  writes — no underscore, no frontend mapping. }
procedure ConfigParser.set(const section, option, value: AnsiString);
var i, j, si: Integer; key: AnsiString; done: Boolean;
begin
  if not has_section(section) then add_section(section);
  key := optionxform(option);
  si := -1;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then si := i;
  if si < 0 then exit;
  done := False;
  for j := 0 to sects[si].count - 1 do
    if sects[si].keys[j] = key then
    begin
      sects[si].vals[j] := value;
      done := True;
    end;
  if done then exit;
  if sects[si].count >= CP_MAX_OPTIONS then exit;
  sects[si].keys[sects[si].count] := key;
  sects[si].vals[sects[si].count] := value;
  sects[si].count := sects[si].count + 1;
end;

function ConfigParser.section_count: Integer;
begin
  section_count := nsect;
end;

function ConfigParser.section_at(i: Integer): AnsiString;
begin
  if (i < 0) or (i >= nsect) then section_at := '' else section_at := sects[i].name;
end;

function CpStrVar(const s: AnsiString): Variant;
{ a str as a NilPy value }
begin
  Result := s;
end;

function ConfigParser.sections: TPyList;
var i: Integer;
begin
  Result := TPyList.Create;
  for i := 0 to nsect - 1 do
    Result.append(CpStrVar(sects[i].name));
end;

function ConfigParser.options(const section: AnsiString): TPyList;
var i, j: Integer;
begin
  Result := TPyList.Create;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then
      for j := 0 to sects[i].count - 1 do
        Result.append(CpStrVar(sects[i].keys[j]));
end;

function ConfigParser.items(const section: AnsiString): TPyList;
var i, j: Integer; pair: TPyList; v: Variant;
begin
  Result := TPyList.Create;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then
      for j := 0 to sects[i].count - 1 do
      begin
        pair := TPyList.Create;
        pair.append(CpStrVar(sects[i].keys[j]));
        pair.append(CpStrVar(sects[i].vals[j]));
        PPyVarRec(@v)^.VType := 7;
        PPyVarRec(@v)^.Payload := Int64(NativeInt(Pointer(pair)));
        PXXObjRetain(Pointer(pair));
        Result.append(v);
      end;
end;

function ConfigParser.sections_text: AnsiString;
var i: Integer; r: AnsiString;
begin
  r := '';
  for i := 0 to nsect - 1 do
  begin
    if i > 0 then r := r + #10;
    r := r + sects[i].name;
  end;
  sections_text := r;
end;

function ConfigParser.option_count(const section: AnsiString): Integer;
var i, n: Integer;
begin
  n := 0;
  for i := 0 to nsect - 1 do
    if sects[i].name = section then n := sects[i].count;
  option_count := n;
end;

function ConfigParser.option_at(const section: AnsiString; i: Integer): AnsiString;
var s, r: Integer; res: AnsiString;
begin
  res := '';
  for s := 0 to nsect - 1 do
    if sects[s].name = section then
      if (i >= 0) and (i < sects[s].count) then res := sects[s].keys[i];
  option_at := res;
end;

function ConfigParser.value_at(const section: AnsiString; i: Integer): AnsiString;
var s: Integer; res: AnsiString;
begin
  res := '';
  for s := 0 to nsect - 1 do
    if sects[s].name = section then
      if (i >= 0) and (i < sects[s].count) then res := sects[s].vals[i];
  value_at := res;
end;

{ One line of INI. Split out as a method rather than a nested procedure so it
  stays plain, single-level Pascal. `cur` is the section being filled. }
procedure ConfigParser.take_line(const raw: AnsiString; var cur: AnsiString);
var line, key, val: AnsiString; eq: Integer;
begin
  line := CpTrim(raw);
  if line = '' then exit;
  if (line[1] = '#') or (line[1] = ';') then exit;      { comment }
  if (line[1] = '[') and (line[Length(line)] = ']') then
  begin
    cur := CpTrim(Copy(line, 2, Length(line) - 2));
    add_section(cur);
    exit;
  end;
  eq := Pos('=', line);
  if eq <= 0 then exit;        { not a key=value line: skipped, as CPython with
                                 strict=False would }
  if cur = '' then exit;       { a value before any section header }
  key := CpTrim(Copy(line, 1, eq - 1));
  val := CpTrim(Copy(line, eq + 1, Length(line) - eq));
  set(cur, key, val);
end;

procedure ConfigParser.read_string(const text: AnsiString);
var i: Integer; line, cur: AnsiString;
begin
  cur := '';
  line := '';
  for i := 1 to Length(text) do
  begin
    if text[i] = #10 then
    begin
      take_line(line, cur);
      line := '';
    end
    else
      line := line + text[i];
  end;
  take_line(line, cur);        { the last line, when there is no final newline }
end;

function ConfigParser.to_string: AnsiString;
var i, j: Integer; r: AnsiString;
begin
  r := '';
  for i := 0 to nsect - 1 do
  begin
    r := r + '[' + sects[i].name + ']' + #10;
    for j := 0 to sects[i].count - 1 do
      r := r + sects[i].keys[j] + ' = ' + sects[i].vals[j] + #10;
    r := r + #10;
  end;
  to_string := r;
end;

function ConfigParser.read(const path: AnsiString): Boolean;
var f: Text; line, text: AnsiString; ok: Boolean;
begin
  ok := False;
  text := '';
  Assign(f, path);
  {$I-}
  Reset(f);
  {$I+}
  if IOResult = 0 then
  begin
    ok := True;
    while not Eof(f) do
    begin
      ReadLn(f, line);
      text := text + line + #10;
    end;
    Close(f);
    read_string(text);
  end;
  read := ok;
end;

function ConfigParser.write(f: TPyFile): Boolean;
var body: AnsiString; b: TPyBytes; i: Integer;
begin
  Result := False;
  if f = nil then Exit;
  body := to_string;
  b := TPyBytes.Create(Length(body));
  for i := 1 to Length(body) do b.put(i - 1, Ord(body[i]));
  f.write(b);
  Result := True;
end;

function ConfigParser.write(const path: AnsiString): Boolean;
var f: Text; ok: Boolean;
begin
  ok := False;
  Assign(f, path);
  {$I-}
  Rewrite(f);
  {$I+}
  if IOResult = 0 then
  begin
    ok := True;
    Write(f, to_string);
    Close(f);
  end;
  write := ok;
end;

end.
