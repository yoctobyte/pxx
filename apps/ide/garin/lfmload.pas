unit lfmload;

{ garin core — load a Lazarus .lfm *text* file into a TDocModel as plain nodes.

  This is NOT the RTTI/streaming loader (lib/rtl/lfm.pas), which instantiates
  live TComponents — the designer is box-emulation and must stay free of live
  widgets. Here we only read the geometry + caption + kind of each `object`
  block into the docmodel, the render-agnostic source of truth.

  LFM shape understood (the common subset):

    object Form1: TForm
      Left = 0
      Top = 0
      Width = 400
      Height = 300
      Caption = 'Form1'
      object Button1: TButton
        Left = 20
        ...
      end
    end

  Nesting gives the parent; Left/Top are parent-relative in LFM and converted to
  absolute surface coords here (the designer paints absolute). Unknown property
  lines and unknown widget types (mapped to wkPanel) are tolerated.

  Implemented as a class rather than nested routines because the pinned compiler
  does not yet support nested routines (docs/progress/backlog/
  feature-nested-routines). The class is the natural carrier for the parse state
  anyway (open-object stack + current node). }

interface

uses docmodel;

type
  TLfmDocReader = class
  public
    Doc: TDocModel;
    Stack: array of Integer;   { open-object node indices, innermost last }
    Depth: Integer;
    Cur: Integer;              { node currently being filled, -1 = none }
    Any: Boolean;              { at least one object seen }
    constructor Create(ADoc: TDocModel);
    function ParentOriginX: Integer;
    function ParentOriginY: Integer;
    procedure SetField(field, v: Integer);   { 0 Left 1 Top 2 Width 3 Height }
    procedure HandleLine(const ln: AnsiString);
    procedure Run(const text: AnsiString);
  end;

{ parse LFM text into doc (assumed fresh/empty). Returns True if >=1 object. }
function LoadLfmText(const text: AnsiString; doc: TDocModel): Boolean;

implementation

uses sysutils;

function KindOf(const typeName: AnsiString): TWidgetKind;
var t: AnsiString;
begin
  t := UpperCase(typeName);
  if t = 'TFORM' then KindOf := wkForm
  else if t = 'TBUTTON' then KindOf := wkButton
  else if t = 'TLABEL' then KindOf := wkLabel
  else if t = 'TEDIT' then KindOf := wkEdit
  else if t = 'TMEMO' then KindOf := wkMemo
  else if t = 'TLISTBOX' then KindOf := wkListBox
  else if t = 'TCHECKBOX' then KindOf := wkCheckBox
  else if t = 'TPANEL' then KindOf := wkPanel
  else KindOf := wkPanel;   { unknown type -> generic box }
end;

function Trim2(const s: AnsiString): AnsiString;
var i, j: Integer;
begin
  i := 1;
  j := Length(s);
  while (i <= j) and ((s[i] = ' ') or (s[i] = #9) or (s[i] = #13)) do Inc(i);
  while (j >= i) and ((s[j] = ' ') or (s[j] = #9) or (s[j] = #13)) do Dec(j);
  if j >= i then Trim2 := Copy(s, i, j - i + 1) else Trim2 := '';
end;

{ first whitespace-separated word of s }
function FirstWord(const s: AnsiString): AnsiString;
var i: Integer;
begin
  i := 1;
  while (i <= Length(s)) and (s[i] <> ' ') and (s[i] <> #9) do Inc(i);
  FirstWord := Copy(s, 1, i - 1);
end;

{ value text after the first '=' on a property line, trimmed }
function RhsOf(const s: AnsiString): AnsiString;
var i: Integer;
begin
  RhsOf := '';
  for i := 1 to Length(s) do
    if s[i] = '=' then
    begin
      RhsOf := Trim2(Copy(s, i + 1, Length(s) - i));
      Exit;
    end;
end;

{ content between the first and last single-quote of s (LFM string literal) }
function Unquote(const s: AnsiString): AnsiString;
var a, b: Integer;
begin
  if (Length(s) >= 1) and (s[1] = '''') then
  begin
    a := 2;
    b := Length(s);
    while (b > a) and (s[b] <> '''') do Dec(b);
    if b > a then Unquote := Copy(s, a, b - a) else Unquote := '';
  end
  else
    Unquote := s;
end;

constructor TLfmDocReader.Create(ADoc: TDocModel);
begin
  Doc := ADoc;
  Depth := 0;
  Cur := -1;
  Any := False;
  SetLength(Stack, 0);
end;

function TLfmDocReader.ParentOriginX: Integer;
begin
  if (Cur >= 0) and (Doc.NodeParent(Cur) >= 0) then
    ParentOriginX := Doc.NodeX(Doc.NodeParent(Cur))
  else
    ParentOriginX := 0;
end;

function TLfmDocReader.ParentOriginY: Integer;
begin
  if (Cur >= 0) and (Doc.NodeParent(Cur) >= 0) then
    ParentOriginY := Doc.NodeY(Doc.NodeParent(Cur))
  else
    ParentOriginY := 0;
end;

procedure TLfmDocReader.SetField(field, v: Integer);
var x, y, w, h: Integer;
begin
  if Cur < 0 then Exit;
  x := Doc.NodeX(Cur); y := Doc.NodeY(Cur);
  w := Doc.NodeW(Cur); h := Doc.NodeH(Cur);
  case field of
    0: x := ParentOriginX + v;   { Left (relative) }
    1: y := ParentOriginY + v;   { Top (relative)  }
    2: w := v;                   { Width  }
    3: h := v;                   { Height }
  end;
  Doc.SetNodeBounds(Cur, x, y, w, h);
end;

procedure TLfmDocReader.HandleLine(const ln: AnsiString);
var body, kw, typeName, ty: AnsiString; colon, j, parent: Integer;
begin
  body := Trim2(ln);
  if body = '' then Exit;
  kw := UpperCase(FirstWord(body));

  if kw = 'OBJECT' then
  begin
    { object <Name>: <Type> — take the type after the colon }
    typeName := '';
    colon := 0;
    for j := 1 to Length(body) do
      if body[j] = ':' then begin colon := j; Break; end;
    if colon > 0 then
      typeName := Trim2(Copy(body, colon + 1, Length(body) - colon));
    ty := FirstWord(typeName);

    if Depth > 0 then parent := Stack[Depth - 1] else parent := -1;
    { default box; coords patched by the property lines that follow }
    Cur := Doc.AddNode(KindOf(ty), '', parent, 0, 0, 80, 24);
    SetLength(Stack, Depth + 1);
    Stack[Depth] := Cur;
    Inc(Depth);
    Any := True;
  end
  else if kw = 'END' then
  begin
    if Depth > 0 then Dec(Depth);
    if Depth > 0 then Cur := Stack[Depth - 1] else Cur := -1;
  end
  else if kw = 'LEFT' then    SetField(0, StrToIntDef(RhsOf(body), 0))
  else if kw = 'TOP' then     SetField(1, StrToIntDef(RhsOf(body), 0))
  else if kw = 'WIDTH' then   SetField(2, StrToIntDef(RhsOf(body), Doc.NodeW(Cur)))
  else if kw = 'HEIGHT' then  SetField(3, StrToIntDef(RhsOf(body), Doc.NodeH(Cur)))
  else if kw = 'CAPTION' then
    if Cur >= 0 then Doc.SetNodeCaption(Cur, Unquote(RhsOf(body)));
end;

procedure TLfmDocReader.Run(const text: AnsiString);
var i, n, lineStart: Integer; ch: Char; line: AnsiString;
begin
  n := Length(text);
  lineStart := 1;
  for i := 1 to n do
  begin
    ch := text[i];
    if ch = #10 then
    begin
      line := Copy(text, lineStart, i - lineStart);
      HandleLine(line);
      lineStart := i + 1;
    end;
  end;
  if lineStart <= n then
  begin
    line := Copy(text, lineStart, n - lineStart + 1);
    HandleLine(line);
  end;
end;

function LoadLfmText(const text: AnsiString; doc: TDocModel): Boolean;
var r: TLfmDocReader;
begin
  r := TLfmDocReader.Create(doc);
  r.Run(text);
  LoadLfmText := r.Any;
end;

end.
