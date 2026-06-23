unit buffer;

{ garin core — editor text buffer. Render-agnostic: holds lines, knows nothing
  about GTK or ANSI. Both faces (eliah, ilja) read it the same way. }

interface

type
  TIdeBuffer = class
  private
    FText: AnsiString;
    FCount: Integer;
    FPath: AnsiString;
  public
    constructor Create;
    function LoadFromFile(const APath: AnsiString): Boolean;
    function Text: AnsiString;
    function LineCount: Integer;
    property Path: AnsiString read FPath;
  end;

{ write AText verbatim to APath (overwriting). Returns False on open failure. }
function WriteAllText(const APath, AText: AnsiString): Boolean;

implementation

uses textfile;

constructor TIdeBuffer.Create;
begin
  FText := '';
  FCount := 0;
  FPath := '';
end;

function TIdeBuffer.LoadFromFile(const APath: AnsiString): Boolean;
var
  f: Text;
  line: AnsiString;
begin
  FPath := APath;
  FText := '';
  FCount := 0;

  Assign(f, APath);
  Reset(f);
  if IOResult <> 0 then
  begin
    Result := False;
    Exit;
  end;

  while not Eof(f) do
  begin
    TextReadLn(f, line);
    if FCount > 0 then
      FText := FText + #10;
    FText := FText + line;
    Inc(FCount);
  end;
  Close(f);
  Result := True;
end;

function TIdeBuffer.Text: AnsiString;
begin
  Result := FText;
end;

function TIdeBuffer.LineCount: Integer;
begin
  Result := FCount;
end;

function WriteAllText(const APath, AText: AnsiString): Boolean;
var f: Text;
begin
  Assign(f, APath);
  Rewrite(f);
  if IOResult <> 0 then
  begin
    Result := False;
    Exit;
  end;
  write(f, AText);
  Close(f);
  Result := True;
end;

end.
