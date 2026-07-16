unit project;

{ garin core — the IDE project model. Render-agnostic: it knows the build inputs
  (which source files, which main unit, where output goes, the unit search paths)
  and turns them into the compiler argv. It knows NOTHING about GTK or ANSI — both
  faces (eliah, ilja) drive the same model, and bochan gate-tests it headless.

  A project serializes to a small line-based text file (`*.pxxproj`):

      # eliah project
      name = MyApp
      main = src/main.pas
      out = /tmp/myapp
      unitpath = lib/rtl
      unitpath = lib/pcl
      file = src/main.pas
      file = src/util.pas

  Blank lines and `#` comments are ignored; `unitpath` and `file` repeat; the
  other keys take the last value seen. BuildArgs turns the model into the argv
  the runner hands the compiler: one `-Fu<dir>` per unit path, then the main
  unit, then the output path. }

interface

type
  TStrArray = array of AnsiString;

  TProject = class
  private
    FName: AnsiString;
    FMain: AnsiString;
    FOut: AnsiString;
    FFiles: array of AnsiString;
    FUnitPaths: array of AnsiString;
    FFileCount: Integer;
    FPathCount: Integer;
  public
    constructor Create;
    procedure Clear;

    procedure AddFile(const APath: AnsiString);
    function FileCount: Integer;
    function GetFile(I: Integer): AnsiString;

    procedure AddUnitPath(const ADir: AnsiString);
    function UnitPathCount: Integer;
    function GetUnitPath(I: Integer): AnsiString;

    { argv for the compiler: [-Fudir...] <main> <out>. Empty if no main unit. }
    function BuildArgs: TStrArray;

    procedure SetName(const S: AnsiString);
    procedure SetMain(const S: AnsiString);
    procedure SetOut(const S: AnsiString);
    function Name: AnsiString;
    function MainUnit: AnsiString;
    function OutPath: AnsiString;

    { serialize / parse the project text (round-trippable). }
    function SaveToText: AnsiString;
    function LoadFromText(const S: AnsiString): Boolean;
    function SaveToFile(const APath: AnsiString): Boolean;
    function LoadFromFile(const APath: AnsiString): Boolean;
  end;

implementation

uses textfile;

constructor TProject.Create;
begin
  Clear;
end;

procedure TProject.Clear;
begin
  FName := '';
  FMain := '';
  FOut := '';
  FFileCount := 0;
  FPathCount := 0;
  SetLength(FFiles, 0);
  SetLength(FUnitPaths, 0);
end;

procedure TProject.AddFile(const APath: AnsiString);
begin
  SetLength(FFiles, FFileCount + 1);
  FFiles[FFileCount] := APath;
  Inc(FFileCount);
end;

function TProject.FileCount: Integer;
begin
  Result := FFileCount;
end;

function TProject.GetFile(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < FFileCount) then Result := FFiles[I] else Result := '';
end;

procedure TProject.AddUnitPath(const ADir: AnsiString);
begin
  SetLength(FUnitPaths, FPathCount + 1);
  FUnitPaths[FPathCount] := ADir;
  Inc(FPathCount);
end;

function TProject.UnitPathCount: Integer;
begin
  Result := FPathCount;
end;

function TProject.GetUnitPath(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < FPathCount) then Result := FUnitPaths[I] else Result := '';
end;

function TProject.BuildArgs: TStrArray;
var i, n: Integer;
begin
  if FMain = '' then begin SetLength(Result, 0); Exit; end;
  { one -Fu per unit path, then main, then out (if set) }
  n := FPathCount + 1;
  if FOut <> '' then Inc(n);
  SetLength(Result, n);
  for i := 0 to FPathCount - 1 do
    Result[i] := '-Fu' + FUnitPaths[i];
  Result[FPathCount] := FMain;
  if FOut <> '' then
    Result[FPathCount + 1] := FOut;
end;

procedure TProject.SetName(const S: AnsiString); begin FName := S; end;
procedure TProject.SetMain(const S: AnsiString); begin FMain := S; end;
procedure TProject.SetOut(const S: AnsiString);  begin FOut := S; end;

function TProject.Name: AnsiString;     begin Result := FName; end;
function TProject.MainUnit: AnsiString; begin Result := FMain; end;
function TProject.OutPath: AnsiString;  begin Result := FOut; end;

function TProject.SaveToText: AnsiString;
var i: Integer; s: AnsiString;
begin
  s := '# eliah project' + #10;
  if FName <> '' then s := s + 'name = ' + FName + #10;
  if FMain <> '' then s := s + 'main = ' + FMain + #10;
  if FOut  <> '' then s := s + 'out = '  + FOut  + #10;
  for i := 0 to FPathCount - 1 do
    s := s + 'unitpath = ' + FUnitPaths[i] + #10;
  for i := 0 to FFileCount - 1 do
    s := s + 'file = ' + FFiles[i] + #10;
  Result := s;
end;

{ trim leading/trailing space, tab, CR }
function PTrim(const s: AnsiString): AnsiString;
var i, j: Integer;
begin
  i := 1; j := Length(s);
  while (i <= j) and ((s[i] = ' ') or (s[i] = #9) or (s[i] = #13)) do Inc(i);
  while (j >= i) and ((s[j] = ' ') or (s[j] = #9) or (s[j] = #13)) do Dec(j);
  if j >= i then Result := Copy(s, i, j - i + 1) else Result := '';
end;

{ split "key = value" on the first '='. False if no '='. }
function SplitKV(const ln: AnsiString; var key, val: AnsiString): Boolean;
var i, eq: Integer;
begin
  eq := 0;
  for i := 1 to Length(ln) do
    if ln[i] = '=' then begin eq := i; Break; end;
  if eq = 0 then begin Result := False; Exit; end;
  key := PTrim(Copy(ln, 1, eq - 1));
  val := PTrim(Copy(ln, eq + 1, Length(ln) - eq));
  Result := True;
end;

function TProject.LoadFromText(const S: AnsiString): Boolean;
var
  i, n, lineStart: Integer;
  ch: Char;
  line, key, val, trimmed: AnsiString;

  procedure Feed(const raw: AnsiString);
  begin
    trimmed := PTrim(raw);
    if (trimmed = '') or (trimmed[1] = '#') then Exit;
    if not SplitKV(trimmed, key, val) then Exit;
    if key = 'name' then FName := val
    else if key = 'main' then FMain := val
    else if key = 'out' then FOut := val
    else if key = 'unitpath' then AddUnitPath(val)
    else if key = 'file' then AddFile(val);
  end;

begin
  Clear;
  n := Length(S);
  lineStart := 1;
  for i := 1 to n do
  begin
    ch := S[i];
    if ch = #10 then
    begin
      line := Copy(S, lineStart, i - lineStart);
      Feed(line);
      lineStart := i + 1;
    end;
  end;
  if lineStart <= n then
    Feed(Copy(S, lineStart, n - lineStart + 1));
  Result := True;
end;

function TProject.SaveToFile(const APath: AnsiString): Boolean;
var f: Text;
begin
  {$I-}
  Assign(f, APath);
  Rewrite(f);
  {$I+}
  if IOResult <> 0 then begin Result := False; Exit; end;
  write(f, SaveToText);
  Close(f);
  Result := True;
end;

function TProject.LoadFromFile(const APath: AnsiString): Boolean;
var
  f: Text;
  line, all: AnsiString;
  first: Boolean;
begin
  {$I-}
  Assign(f, APath);
  Reset(f);
  {$I+}
  if IOResult <> 0 then begin Result := False; Exit; end;
  all := '';
  first := True;
  while not Eof(f) do
  begin
    TextReadLn(f, line);
    if not first then all := all + #10;
    all := all + line;
    first := False;
  end;
  Close(f);
  Result := LoadFromText(all);
end;

end.
</content>
