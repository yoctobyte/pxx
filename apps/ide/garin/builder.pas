unit builder;

{ garin core — parse compiler output into a render-agnostic diagnostic list.

  The frankonpiler emits one diagnostic per line as:

      <prefix>:<line>: <message>          e.g.  pascal26:3: error: undefined variable (x)

  We key off "a number between the first two colons": that line number plus the
  trailing message become a diagnostic. Lines without that shape (the `ok: ...`
  success line, blanks, banners) are ignored.

  A diagnostic MAY be followed by an indented continuation naming the file the
  offending token actually came from:

      pascal26:63: error: expected expression
        in: test/incdiag/badinc.inc
        near:  procedure Bogus  begin if >>> then  end

  This unit used to say "the source file is the caller's business (the compiler
  names one main unit)". That stopped being true on 2026-08-21
  (bug-a-a-parse-error-in-a-used-unit-reports-a-line-in-no-file): when the token
  comes from an include or a `uses`d unit, the line number is a real line OF
  THAT FILE, and the `in:` line is the only thing that says which. Keeping the
  number and dropping the path is worse than having neither -- it jumps
  confidently into the wrong file. So DiagFile now carries it.

  DiagFile is '' when there was no `in:` line, and '' still means exactly what
  the old comment said: the main unit, which is the caller's business because
  the caller is the one who named it. The compiler deliberately does NOT emit
  `in:` for the main source (test_incdiag_main_fail asserts its absence), so
  this is a real distinction and not a missing value.

  Faces (eliah error list, ilja) render the same data and use it to jump the
  editor. No GTK/ANSI here. }

interface

type
  TDiagList = class
  private
    FLines: array of Integer;
    FMsgs: array of AnsiString;
    FFiles: array of AnsiString;   { '' = the main unit; see the header }
    FCount: Integer;
  public
    constructor Create;
    procedure Clear;
    procedure Parse(const output: AnsiString);   { append diagnostics found in output }
    function Count: Integer;
    function DiagLine(I: Integer): Integer;
    function DiagMsg(I: Integer): AnsiString;
    function DiagFile(I: Integer): AnsiString;   { '' = the main unit }
  end;

implementation

uses sysutils;

constructor TDiagList.Create;
begin
  FCount := 0;
  SetLength(FLines, 0);
  SetLength(FMsgs, 0);
  SetLength(FFiles, 0);
end;

procedure TDiagList.Clear;
begin
  FCount := 0;
  SetLength(FLines, 0);
  SetLength(FMsgs, 0);
  SetLength(FFiles, 0);
end;

function IsDigits(const s: AnsiString): Boolean;
var i: Integer;
begin
  IsDigits := Length(s) > 0;
  for i := 1 to Length(s) do
    if (s[i] < '0') or (s[i] > '9') then begin IsDigits := False; Exit; end;
end;

function Trim2(const s: AnsiString): AnsiString;
var i, j: Integer;
begin
  i := 1; j := Length(s);
  while (i <= j) and ((s[i] = ' ') or (s[i] = #9) or (s[i] = #13)) do Inc(i);
  while (j >= i) and ((s[j] = ' ') or (s[j] = #9) or (s[j] = #13)) do Dec(j);
  if j >= i then Trim2 := Copy(s, i, j - i + 1) else Trim2 := '';
end;

{ if ln is the indented `  in: <path>` continuation, set path and return True.

  Keyed on the INDENT plus the literal `in:`, not on colon-splitting: a path may
  contain a colon, and the colon-splitting used for diagnostics would then take
  a bite out of it. The indent is also what distinguishes a continuation from a
  new diagnostic, which is the property the compiler's format guarantees. }
function ParseInFile(const ln: AnsiString; var path: AnsiString): Boolean;
var i: Integer; rest: AnsiString;
begin
  ParseInFile := False;
  i := 1;
  while (i <= Length(ln)) and ((ln[i] = ' ') or (ln[i] = #9)) do Inc(i);
  if i = 1 then Exit;                     { not indented -> not a continuation }
  if i + 2 > Length(ln) then Exit;
  if Copy(ln, i, 3) <> 'in:' then Exit;
  rest := Trim2(Copy(ln, i + 3, Length(ln) - i - 2));
  if rest = '' then Exit;
  path := rest;
  ParseInFile := True;
end;

{ if ln is a diagnostic, set lineNo + msg and return True }
function ParseLine(const ln: AnsiString; var lineNo: Integer; var msg: AnsiString): Boolean;
var c1, c2, i: Integer; numStr: AnsiString;
begin
  ParseLine := False;
  c1 := 0;
  for i := 1 to Length(ln) do
    if ln[i] = ':' then begin c1 := i; Break; end;
  if c1 = 0 then Exit;
  c2 := 0;
  for i := c1 + 1 to Length(ln) do
    if ln[i] = ':' then begin c2 := i; Break; end;
  if c2 = 0 then Exit;
  numStr := Copy(ln, c1 + 1, c2 - c1 - 1);
  if not IsDigits(numStr) then Exit;
  lineNo := StrToIntDef(numStr, 0);
  msg := Trim2(Copy(ln, c2 + 1, Length(ln) - c2));
  ParseLine := True;
end;

procedure TDiagList.Parse(const output: AnsiString);
var
  i, n, lineStart, lno: Integer;
  ch: Char;
  line, msg: AnsiString;

  procedure Feed(const ln: AnsiString);
  var path: AnsiString;
  begin
    if ParseLine(ln, lno, msg) then
    begin
      SetLength(FLines, FCount + 1);
      SetLength(FMsgs, FCount + 1);
      SetLength(FFiles, FCount + 1);
      FLines[FCount] := lno;
      FMsgs[FCount] := msg;
      FFiles[FCount] := '';
      Inc(FCount);
    end
    else if ParseInFile(ln, path) then
    begin
      { attaches to the diagnostic ABOVE it. Only when that one has no file
        yet: one `in:` per diagnostic is the format, so a second would mean we
        misread something, and overwriting would hide that. With no diagnostic
        above at all there is nothing to attach to -- drop it rather than
        inventing a diagnostic that the compiler did not report. }
      if (FCount > 0) and (FFiles[FCount - 1] = '') then
        FFiles[FCount - 1] := path;
    end;
  end;

begin
  n := Length(output);
  lineStart := 1;
  for i := 1 to n do
  begin
    ch := output[i];
    if ch = #10 then
    begin
      line := Copy(output, lineStart, i - lineStart);
      Feed(line);
      lineStart := i + 1;
    end;
  end;
  if lineStart <= n then
    Feed(Copy(output, lineStart, n - lineStart + 1));
end;

function TDiagList.Count: Integer;
begin
  Count := FCount;
end;

function TDiagList.DiagLine(I: Integer): Integer;
begin
  if (I >= 0) and (I < FCount) then DiagLine := FLines[I] else DiagLine := 0;
end;

function TDiagList.DiagMsg(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < FCount) then DiagMsg := FMsgs[I] else DiagMsg := '';
end;

function TDiagList.DiagFile(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < FCount) then DiagFile := FFiles[I] else DiagFile := '';
end;

end.
