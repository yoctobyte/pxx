unit selection;

{ garin core — the shared selection model + code↔designer location mapping.
  Render-agnostic: holds the "current selection" (a node index in the active
  doc model) and maps a component name to/from its `.lfm` declaration line. The
  faces (eliah, ilja) read this to keep the designer highlight and the editor
  caret in sync; commands operate on the selection, never on layout state. No
  GTK/ANSI here — fully bochan-testable. }

interface

uses docmodel;

type
  TSelectionModel = class
  private
    FDoc: TDocModel;
    FSel: Integer;        { selected node index, -1 = none }
    FChanges: Integer;    { bumped on every actual change (test/observe hook) }
  public
    constructor Create(ADoc: TDocModel);
    procedure SetDoc(ADoc: TDocModel);
    { select by node index; out-of-range clears. No-op (no change bump) if already
      selected. }
    procedure Select(I: Integer);
    { select the node whose Name matches; unknown name clears. }
    procedure SelectByName(const AName: AnsiString);
    procedure Clear;
    function Selected: Integer;
    function SelectedName: AnsiString;
    function Changes: Integer;
  end;

{ Line (0-based) of the `object <AName>: <Type>` declaration for AName, or -1.
  Matches the component identifier between the `object` keyword and the colon. }
function LfmFindObjectLine(const text, AName: AnsiString): Integer;

{ If line LineIdx (0-based) of text is an `object <Name>: <Type>` header, return
  Name; otherwise ''. The inverse of LfmFindObjectLine for one line. }
function LfmObjectNameAt(const text: AnsiString; LineIdx: Integer): AnsiString;

{ ---- command surface (wire an event handler) ---- }

{ Conventional handler name for a component event: <CompName><Event>, e.g.
  ('BtnOk','Click') -> 'BtnOkClick'. }
function EventHandlerName(const CompName, Event: AnsiString): AnsiString;

{ A bare Pascal handler stub for HandlerName. }
function EventHandlerStub(const HandlerName: AnsiString): AnsiString;

{ True if code already declares `procedure <HandlerName>(` (any whitespace run
  after `procedure`). Avoids appending a duplicate stub. }
function CodeHasHandler(const code, HandlerName: AnsiString): Boolean;

implementation

constructor TSelectionModel.Create(ADoc: TDocModel);
begin
  FDoc := ADoc;
  FSel := -1;
  FChanges := 0;
end;

procedure TSelectionModel.SetDoc(ADoc: TDocModel);
begin
  FDoc := ADoc;
  FSel := -1;
  FChanges := FChanges + 1;
end;

procedure TSelectionModel.Select(I: Integer);
var n: Integer;
begin
  n := I;
  if (FDoc = nil) or (n < 0) or (n >= FDoc.Count) then n := -1;
  if n = FSel then Exit;
  FSel := n;
  FChanges := FChanges + 1;
end;

procedure TSelectionModel.SelectByName(const AName: AnsiString);
begin
  if FDoc = nil then Select(-1)
  else Select(FDoc.FindByName(AName));
end;

procedure TSelectionModel.Clear;
begin
  Select(-1);
end;

function TSelectionModel.Selected: Integer;
begin
  Selected := FSel;
end;

function TSelectionModel.SelectedName: AnsiString;
begin
  if (FDoc = nil) or (FSel < 0) then SelectedName := ''
  else SelectedName := FDoc.NodeName(FSel);
end;

function TSelectionModel.Changes: Integer;
begin
  Changes := FChanges;
end;

{ ---------- .lfm line mapping ---------- }

function Trim2(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  a := 1; b := Length(s);
  while (a <= b) and ((s[a] = ' ') or (s[a] = #9)) do Inc(a);
  while (b >= a) and ((s[b] = ' ') or (s[b] = #9) or (s[b] = #13)) do Dec(b);
  Trim2 := Copy(s, a, b - a + 1);
end;

{ Parse `object <Name>: <Type>` (or `inherited`/`inline`) -> Name, else ''. }
function ObjectNameOfLine(const line: AnsiString): AnsiString;
var s, kw: AnsiString; i, sp, colon: Integer;
begin
  ObjectNameOfLine := '';
  s := Trim2(line);
  { leading keyword }
  sp := 0;
  for i := 1 to Length(s) do
    if (s[i] = ' ') or (s[i] = #9) then begin sp := i; Break; end;
  if sp = 0 then Exit;
  kw := Copy(s, 1, sp - 1);
  if (kw <> 'object') and (kw <> 'inherited') and (kw <> 'inline') then Exit;
  { name runs from after the keyword to the colon }
  colon := 0;
  for i := sp + 1 to Length(s) do
    if s[i] = ':' then begin colon := i; Break; end;
  if colon = 0 then Exit;
  ObjectNameOfLine := Trim2(Copy(s, sp + 1, colon - sp - 1));
end;

{ the text of line LineIdx (0-based), split on #10 }
function NthLine(const text: AnsiString; LineIdx: Integer): AnsiString;
var i, n, start, idx: Integer;
begin
  NthLine := '';
  if LineIdx < 0 then Exit;
  n := Length(text);
  start := 1;
  idx := 0;
  for i := 1 to n do
    if text[i] = #10 then
    begin
      if idx = LineIdx then begin NthLine := Copy(text, start, i - start); Exit; end;
      Inc(idx);
      start := i + 1;
    end;
  if (idx = LineIdx) and (start <= n) then NthLine := Copy(text, start, n - start + 1);
end;

function LfmObjectNameAt(const text: AnsiString; LineIdx: Integer): AnsiString;
begin
  LfmObjectNameAt := ObjectNameOfLine(NthLine(text, LineIdx));
end;

{ first index >= from where sub occurs in s (1-based), or 0 }
function FindFrom(const s, sub: AnsiString; from: Integer): Integer;
var i, j, n, m: Integer; ok: Boolean;
begin
  FindFrom := 0;
  n := Length(s); m := Length(sub);
  if (m = 0) or (m > n) then Exit;
  for i := from to n - m + 1 do
  begin
    ok := True;
    for j := 1 to m do
      if s[i + j - 1] <> sub[j] then begin ok := False; Break; end;
    if ok then begin FindFrom := i; Exit; end;
  end;
end;

function EventHandlerName(const CompName, Event: AnsiString): AnsiString;
begin
  EventHandlerName := CompName + Event;
end;

function EventHandlerStub(const HandlerName: AnsiString): AnsiString;
begin
  EventHandlerStub :=
    'procedure ' + HandlerName + '(Sender: TObject);' + #10 +
    'begin' + #10 +
    '' + #10 +
    'end;' + #10;
end;

function CodeHasHandler(const code, HandlerName: AnsiString): Boolean;
var p, n: Integer;
begin
  CodeHasHandler := False;
  if HandlerName = '' then Exit;
  p := 1;
  repeat
    p := FindFrom(code, 'procedure ', p);
    if p = 0 then Exit;
    n := p + Length('procedure ');
    while (n <= Length(code)) and ((code[n] = ' ') or (code[n] = #9)) do Inc(n);
    if FindFrom(code, HandlerName + '(', n) = n then
    begin CodeHasHandler := True; Exit; end;
    p := p + 1;
  until False;
end;

function LfmFindObjectLine(const text, AName: AnsiString): Integer;
var i, n, start, idx: Integer;
begin
  LfmFindObjectLine := -1;
  if AName = '' then Exit;
  n := Length(text);
  start := 1;
  idx := 0;
  for i := 1 to n do
    if text[i] = #10 then
    begin
      if ObjectNameOfLine(Copy(text, start, i - start)) = AName then
      begin LfmFindObjectLine := idx; Exit; end;
      Inc(idx);
      start := i + 1;
    end;
  if (start <= n) and (ObjectNameOfLine(Copy(text, start, n - start + 1)) = AName) then
    LfmFindObjectLine := idx;
end;

end.
