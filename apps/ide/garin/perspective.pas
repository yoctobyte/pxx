unit perspective;

{ garin core — the IDE perspective model. A perspective is a named layout: a set
  of panes along one axis, each with a minimum size, a priority, and a chosen
  visibility. It is render-agnostic (no GTK/ANSI) and bochan-testable; the faces
  (eliah) map each pane to a real splitter and apply the model's decisions.

  Two jobs:

  1. Visibility presets — a pane can be hidden by the perspective (e.g. the Code
     layout hides the designer column). `Visible` is that choice.

  2. Priority compacting — when the available space cannot hold the minimum sizes
     of all *visible* panes, drop the lowest-priority pane (then the next, …)
     until the rest fit, instead of squashing everyone below their minimum. This
     is the predictable answer to "shrink the window and keep things usable".
     `Compact(available)` recomputes the forced-collapse set; `IsShown` then
     reports visible-and-survived.

  Perspectives serialize to a small line-based text (round-trippable), like the
  project descriptor:

      perspective Code
      pane left   min=120 pri=80 vis=1
      pane center min=200 pri=90 vis=1
      pane right  min=160 pri=40 vis=0
}

interface

type
  TPaneInfo = record
    Id: AnsiString;
    MinSize: Integer;
    Priority: Integer;     { higher = more important; collapsed last }
    Visible: Boolean;      { the perspective's own show/hide choice }
  end;

  TPerspective = class
  private
    FName: AnsiString;
    FPanes: array of TPaneInfo;
    FForced: array of Boolean;   { collapsed by compacting (not by choice) }
    FCount: Integer;
  public
    constructor Create;
    procedure Clear;

    procedure SetName(const s: AnsiString);
    function Name: AnsiString;

    procedure AddPane(const AId: AnsiString; AMin, APriority: Integer; AVisible: Boolean);
    function PaneCount: Integer;
    function PaneId(I: Integer): AnsiString;
    function PaneMin(I: Integer): Integer;
    function PanePriority(I: Integer): Integer;
    function PaneVisible(I: Integer): Boolean;
    procedure SetVisible(I: Integer; V: Boolean);
    function IndexOf(const AId: AnsiString): Integer;

    { recompute the forced-collapse set for the given available span }
    procedure Compact(AAvailable: Integer);
    { visible by the perspective AND surviving the last Compact }
    function IsShown(I: Integer): Boolean;
    { forced-collapsed by the last Compact (distinct from a hidden-by-choice pane) }
    function IsForced(I: Integer): Boolean;

    function SaveToText: AnsiString;
    function LoadFromText(const S: AnsiString): Boolean;
  end;

implementation

uses sysutils;

constructor TPerspective.Create;
begin
  Clear;
end;

procedure TPerspective.Clear;
begin
  FName := '';
  FCount := 0;
  SetLength(FPanes, 0);
  SetLength(FForced, 0);
end;

procedure TPerspective.SetName(const s: AnsiString); begin FName := s; end;
function TPerspective.Name: AnsiString; begin Result := FName; end;

procedure TPerspective.AddPane(const AId: AnsiString; AMin, APriority: Integer; AVisible: Boolean);
begin
  SetLength(FPanes, FCount + 1);
  SetLength(FForced, FCount + 1);
  FPanes[FCount].Id := AId;
  FPanes[FCount].MinSize := AMin;
  FPanes[FCount].Priority := APriority;
  FPanes[FCount].Visible := AVisible;
  FForced[FCount] := False;
  FCount := FCount + 1;
end;

function TPerspective.PaneCount: Integer; begin Result := FCount; end;

function TPerspective.PaneId(I: Integer): AnsiString;
begin
  if (I >= 0) and (I < FCount) then Result := FPanes[I].Id else Result := '';
end;

function TPerspective.PaneMin(I: Integer): Integer;
begin
  if (I >= 0) and (I < FCount) then Result := FPanes[I].MinSize else Result := 0;
end;

function TPerspective.PanePriority(I: Integer): Integer;
begin
  if (I >= 0) and (I < FCount) then Result := FPanes[I].Priority else Result := 0;
end;

function TPerspective.PaneVisible(I: Integer): Boolean;
begin
  if (I >= 0) and (I < FCount) then Result := FPanes[I].Visible else Result := False;
end;

procedure TPerspective.SetVisible(I: Integer; V: Boolean);
begin
  if (I >= 0) and (I < FCount) then FPanes[I].Visible := V;
end;

function TPerspective.IndexOf(const AId: AnsiString): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to FCount - 1 do
    if FPanes[i].Id = AId then begin Result := i; Exit; end;
end;

procedure TPerspective.Compact(AAvailable: Integer);
var i, sumMin, shown, lowIdx, lowPri: Integer;
begin
  for i := 0 to FCount - 1 do FForced[i] := False;
  { drop the lowest-priority active pane until the minimums fit (keep >= 1) }
  while True do
  begin
    sumMin := 0; shown := 0; lowIdx := -1; lowPri := 0;
    for i := 0 to FCount - 1 do
      if FPanes[i].Visible and (not FForced[i]) then
      begin
        sumMin := sumMin + FPanes[i].MinSize;
        shown := shown + 1;
        if (lowIdx < 0) or (FPanes[i].Priority < lowPri) then
        begin
          lowPri := FPanes[i].Priority;
          lowIdx := i;
        end;
      end;
    if (sumMin <= AAvailable) or (shown <= 1) or (lowIdx < 0) then Break;
    FForced[lowIdx] := True;
  end;
end;

function TPerspective.IsShown(I: Integer): Boolean;
begin
  if (I >= 0) and (I < FCount) then
    Result := FPanes[I].Visible and (not FForced[I])
  else
    Result := False;
end;

function TPerspective.IsForced(I: Integer): Boolean;
begin
  if (I >= 0) and (I < FCount) then Result := FForced[I] else Result := False;
end;

function BoolStr(b: Boolean): AnsiString;
begin
  if b then Result := '1' else Result := '0';
end;

function TPerspective.SaveToText: AnsiString;
var i: Integer; s: AnsiString;
begin
  s := 'perspective ' + FName + #10;
  for i := 0 to FCount - 1 do
    s := s + 'pane ' + FPanes[i].Id +
         ' min=' + IntToStr(FPanes[i].MinSize) +
         ' pri=' + IntToStr(FPanes[i].Priority) +
         ' vis=' + BoolStr(FPanes[i].Visible) + #10;
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

{ split a whitespace-separated line into the next token; returns token, advances p }
function NextTok(const s: AnsiString; var p: Integer): AnsiString;
var st: Integer;
begin
  while (p <= Length(s)) and ((s[p] = ' ') or (s[p] = #9)) do Inc(p);
  st := p;
  while (p <= Length(s)) and (s[p] <> ' ') and (s[p] <> #9) do Inc(p);
  Result := Copy(s, st, p - st);
end;

{ value after "key=" in token "key=value" }
function TokVal(const tok: AnsiString): AnsiString;
var i: Integer;
begin
  Result := '';
  for i := 1 to Length(tok) do
    if tok[i] = '=' then begin Result := Copy(tok, i + 1, Length(tok) - i); Exit; end;
end;

function TPerspective.LoadFromText(const S: AnsiString): Boolean;
var
  i, n, lineStart, p: Integer;
  ch: Char;
  line, w, id: AnsiString;
  mn, pri: Integer; vis: Boolean;

  procedure Feed(const raw: AnsiString);
  begin
    line := PTrim(raw);
    if line = '' then Exit;
    p := 1;
    w := NextTok(line, p);
    if w = 'perspective' then
      FName := PTrim(Copy(line, p, Length(line) - p + 1))
    else if w = 'pane' then
    begin
      id := NextTok(line, p);
      mn := StrToIntDef(TokVal(NextTok(line, p)), 0);
      pri := StrToIntDef(TokVal(NextTok(line, p)), 0);
      vis := TokVal(NextTok(line, p)) <> '0';
      AddPane(id, mn, pri, vis);
    end;
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
      Feed(Copy(S, lineStart, i - lineStart));
      lineStart := i + 1;
    end;
  end;
  if lineStart <= n then Feed(Copy(S, lineStart, n - lineStart + 1));
  Result := True;
end;

end.
</content>
