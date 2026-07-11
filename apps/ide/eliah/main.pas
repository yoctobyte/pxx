program eliah;

{ Eliah — GTK face of the IDE.

  A single sizable window (no multi-window / modal). Menu + toolbar on top; below
  them the whole pane area is ONE nested-TPaned splitter tree (RootPaned), so
  every divider is a draggable splitter and the layout is data, not absolute math:

    [ Up  Compile  Run … ]                         (toolbar — outside the tree)
    +--------+----------------------+-------------+
    | proj   |   editor             |  designer   |
    | tree   |                      |             |
    |--------+----------------------+-------------+
    | errors |   build / run output | inspector   |
    +--------+----------------------+-------------+

    RootPaned(H) ─┬ colLeft(V):  tree / errors
                  └ midRight(H) ─┬ colCenter(V): editor / output
                                 └ colRight(V):  designer / colInspector(V): props / valueEdit

  GtkPaned owns all splitter sizing; we seed initial handle positions once on the
  first allocation (OnFormResize) and only resize RootPaned on window-resize.

  Working: the project tree lists a directory (click a folder to descend, "../"
  to go up, a file to open it in the editor through the garin buffer); Compile
  runs the pinned compiler on the open .pas and shows its output; Run executes
  the built binary. The right column is the designer: a TPaintBox paints the
  garin docmodel as emulated boxes, clicking a box hit-tests the model and shows
  a selection outline + the node's fields in the object-inspector pane below. }

uses gtk3, controls, stdctrls, extctrls, graphics, forms, menus, sysutils,
     buffer, runner, docmodel, designer, lfmload, builder, project, perspective,
     registry, typinfo, selection, classes_lite, resources, lfm;

{ Eliah's own window chrome is defined in eliah.lfm and streamed into TEliahForm
  (dogfooding the .lfm streamer). The toolbar + nested-TPaned splitter tree + leaf
  widgets come from the resource; the menu, palette population, designer, and
  reflow stay in code. }
{$R TEliahForm eliah.lfm}

const
  W_WIN     = 1100;
  H_WIN     = 700;
  W_TREE    = 240;
  W_RIGHT   = 300;
  H_BOTTOM  = 200;
  ERR_H     = 150;        { error-list height at the bottom of the left column }
  TOOLBAR_H = 104;       { toolbar strip: button row (26px at Top=3) + the
                           component tab bar (TTabBar at Top=36, ~64px) }
  PXX_PATH  = 'stable_linux_amd64/default/pinned';
  BUILD_OUT = '/tmp/eliah_build';
  SAMPLE_LFM = 'apps/ide/eliah/sample.lfm';
  EXAMPLES_DIR = 'apps/ide/eliah/examples';   { demo projects; default start dir }

type
  { The whole window is streamed from eliah.lfm into this form. The widget fields
    below are PUBLISHED so the streamer binds each to the matching .lfm object;
    the event handlers are PUBLISHED so .lfm OnX = OnY bindings resolve. Everything
    else (designer, selection model, project, undo, …) is plain state. }
  TEliahForm = class(TForm)
  public
    Diags: TDiagList;
    Proj: TProject;        { active project; empty MainUnit => single-file compile }
    FEditRow: Integer;     { which inspector row the value edit targets, -1 none }
    FBagBase: Integer;     { inspector row index where the extra-property rows start }
    FBagNames: array of AnsiString; { property name backing each extra-property row }
    PaletteNames: array of AnsiString; { class name backing each palette row }
    PlaceMode: Boolean;    { next designer click drops a new widget }
    { tabbed component bar (feature-eliah-component-tabbar): registry-driven
      like the combo; clicking a component button selects that palette row and
      arms Place. BarRows maps each bar button to its PaletteNames row. }
    CompBar: TTabBar;
    BarButtons: array of TButton;
    BarRows: array of Integer;
    Dsn: TDesigner;
    Sel: TSelectionModel;  { shared selection — designer + editor stay in sync via it }
    Persp: TPerspective;   { current layout: column visibility + priority compacting }
    panedSeeded: Boolean;  { initial handle positions applied on first allocation }
    startPersp: AnsiString; { perspective applied once after the first allocation }
    dir, curFile, designPath, pendingSnap: AnsiString;
    undoStack: array of AnsiString;
    undoCount: Integer;
    lastW: Integer;        { last width seen by OnFormResize (loop guard) }
    paths: array of AnsiString;
    isdirs: array of Boolean;
    nItems: Integer;
    constructor Create(AOwner: TComponent); override;
    procedure LoadDir(const d: AnsiString);
    procedure OnOpenFolder(Sender: TObject);
    procedure OnExit(Sender: TObject);
    procedure OnExampleClick(Sender: TObject);   { File->Examples item -> open it }
    procedure PushUndo(const snap: AnsiString);
    procedure OpenDesign(const path: AnsiString);
    procedure Relayout(w, h: Integer);
    procedure OnFormResize(Sender: TControl; w, h: Integer);
    procedure ShowInspector(idx: Integer);
    procedure AddBagRow(d: TDocModel; idx: Integer; const nm: AnsiString);
    function BagRowShown(const nm: AnsiString): Boolean;
    procedure SelectNode(idx: Integer);
    procedure EditorToSelection;
    procedure SelectFromEditorLine(ln: Integer);
    procedure UpdateTitle;
    procedure ApplyEdit;
    procedure OnToggleLeft(Sender: TObject);
    procedure OnToggleOutput(Sender: TObject);
    procedure OnToggleRight(Sender: TObject);
    procedure SetPerspective(const name: AnsiString);
    procedure ApplyLayout(w: Integer);
    procedure OnPerspCode(Sender: TObject);
    procedure OnPerspDesign(Sender: TObject);
    procedure OnPerspSplit(Sender: TObject);
  published
    { streamed widgets — names match eliah.lfm objects }
    Tree: TListBox;
    Errors: TListBox;
    Props: TListBox;
    Editor: TMemo;
    Output: TMemo;
    ValueEdit: TEdit;
    Palette: TComboBox;
    PlaceBtn: TButton;
    DesignBox: TPaintBox;
    RootPaned: TPaned;     { fills the content area; the whole pane layout is its subtree }
    colLeft: TPaned;
    midRight: TPaned;
    colCenter: TPaned;
    colRight: TPaned;
    colInspector: TPaned;
    { pane header strips: TBox(header button + content), collapse via the
      existing OnToggle* handlers; header caption chevron flips with state }
    leftBox: TBox;
    leftHdr: TButton;
    rightBox: TBox;
    rightHdr: TButton;
    outputBox: TBox;
    outputHdr: TButton;
    { event handlers bound from eliah.lfm }
    procedure OnUp(Sender: TObject);
    procedure OnCompile(Sender: TObject);
    procedure OnRun(Sender: TObject);
    procedure OnSave(Sender: TObject);
    procedure OnDelete(Sender: TObject);
    procedure OnNew(Sender: TObject);
    procedure OnUndo(Sender: TObject);
    procedure OnTreeClick(Sender: TObject);
    procedure OnErrorClick(Sender: TObject);
    procedure OnPlaceToggle(Sender: TObject);
    { NOTE Sender is typed TButton, not TObject: a TObject-typed parameter
      arrives 32-bit-truncated (bug-tobject-param-truncated-32bit), which
      broke the identity search below. Concrete class params are fine. }
    procedure OnPaletteButton(Sender: TButton);
    procedure OnPickFromCaret(Sender: TObject);
    procedure OnWireOnClick(Sender: TObject);
    procedure OnPropClick(Sender: TObject);
    procedure OnValueKey(Sender: TControl; KeyCode: Integer);
    procedure OnDesignPaint(Sender: TControl; Canvas: TCanvas);
    procedure OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseMove(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseUp(Sender: TControl; Button, X, Y: Integer);
  end;

{ A registered visual component class name -> the docmodel kind the designer can
  place for it. Returns False for components the box-emulation model can't place
  yet (e.g. TComboBox/TPaintBox/TPaned/TForm) — those are filtered out of the
  palette. This is the only PCL-name -> kind policy; the registry stays generic. }
function CompPlaceKind(const clsName: AnsiString; var k: TWidgetKind): Boolean;
begin
  CompPlaceKind := True;
  if      clsName = 'TButton'   then k := wkButton
  else if clsName = 'TLabel'    then k := wkLabel
  else if clsName = 'TEdit'     then k := wkEdit
  else if clsName = 'TMemo'     then k := wkMemo
  else if clsName = 'TListBox'  then k := wkListBox
  else if clsName = 'TCheckBox' then k := wkCheckBox
  else if clsName = 'TPanel'    then k := wkPanel
  else if clsName = 'TTimer'    then k := wkTimer   { non-visual -> tray }
  else if clsName = 'TMenu'     then k := wkMenu    { non-visual -> tray }
  else CompPlaceKind := False;
end;

{ Palette display label: drop a leading 'T' from the class name (TButton -> Button). }
function CompDisplay(const clsName: AnsiString): AnsiString;
begin
  if (Length(clsName) > 1) and (clsName[1] = 'T') then
    CompDisplay := Copy(clsName, 2, Length(clsName) - 1)
  else
    CompDisplay := clsName;
end;

{ read a published property's name from its RTTI (frozen NamePtr string) }
function PropName(p: PPropInfo): AnsiString;
var ps: PString;
begin
  PropName := '';
  if p = nil then Exit;
  ps := p^.NamePtr;
  PropName := ps^;
end;

{ a property already shown as a modelled inspector row (mapped to a node field),
  so it is NOT repeated in the RTTI extra-property list. }
function IsModelledProp(const nm: AnsiString): Boolean;
begin
  IsModelledProp := (nm = 'Caption') or (nm = 'Name') or (nm = 'Left') or
    (nm = 'Top') or (nm = 'Width') or (nm = 'Height');
end;

{ case-insensitive '.lfm' suffix test }
function EndsWithLfm(const s: AnsiString): Boolean;
var n: Integer; tail: AnsiString;
begin
  n := Length(s);
  if n < 4 then begin EndsWithLfm := False; Exit; end;
  tail := LowerCase(Copy(s, n - 3, 4));
  EndsWithLfm := tail = '.lfm';
end;

{ a NUL byte (or a control char that isn't tab/newline/return) in the first few KB
  means the file is not text — opening it raw garbles the editor and a large one is
  slow to set into the gtk buffer. }
function LooksBinary(const s: AnsiString): Boolean;
var i, n: Integer; c: Integer;
begin
  LooksBinary := False;
  n := Length(s);
  if n > 4096 then n := 4096;
  for i := 1 to n do
  begin
    c := Ord(s[i]);
    if (c = 0) or ((c < 32) and (c <> 9) and (c <> 10) and (c <> 13)) then
    begin LooksBinary := True; Exit; end;
  end;
end;

{ a classic offset + hex + ascii dump of the first maxBytes of s }
function HexPreview(const s: AnsiString; maxBytes: Integer): AnsiString;
const hexd = '0123456789abcdef';
var i, n, col, c: Integer; line, asc, r: AnsiString;
begin
  n := Length(s);
  if n > maxBytes then n := maxBytes;
  r := '';
  line := ''; asc := ''; col := 0;
  for i := 1 to n do
  begin
    c := Ord(s[i]);
    line := line + hexd[(c shr 4) + 1] + hexd[(c and 15) + 1] + ' ';
    if (c >= 32) and (c < 127) then asc := asc + s[i] else asc := asc + '.';
    col := col + 1;
    if col = 16 then
    begin r := r + line + ' ' + asc + #10; line := ''; asc := ''; col := 0; end;
  end;
  if col > 0 then
  begin
    while col < 16 do begin line := line + '   '; col := col + 1; end;
    r := r + line + ' ' + asc + #10;
  end;
  HexPreview := r;
end;

function ParentDir(const d: AnsiString): AnsiString;
var i: Integer;
begin
  for i := Length(d) downto 1 do
    if d[i] = '/' then
    begin
      if i = 1 then ParentDir := '/' else ParentDir := Copy(d, 1, i - 1);
      Exit;
    end;
  ParentDir := '.';
end;

procedure TEliahForm.LoadDir(const d: AnsiString);
var list: TFileInfoArray; i: Integer; nm: AnsiString;
begin
  dir := d;
  Tree.Clear;
  nItems := 0;
  SetLength(paths, 1024);
  SetLength(isdirs, 1024);

  Tree.AddItem('../');
  paths[nItems] := ParentDir(d);
  isdirs[nItems] := True;
  nItems := nItems + 1;

  if GetDirectoryContents(d, list) then
    for i := 0 to Length(list) - 1 do
    begin
      nm := list[i].Name;
      if (nm = '.') or (nm = '..') then continue;
      if list[i].IsDir then Tree.AddItem(nm + '/') else Tree.AddItem(nm);
      if nItems < 1024 then
      begin
        paths[nItems] := d + '/' + nm;
        isdirs[nItems] := list[i].IsDir;
        nItems := nItems + 1;
      end;
    end;

  { auto-load a project descriptor if the folder has one; on miss the model
    stays empty (MainUnit='') and Compile falls back to single-file. }
  Proj.Clear;
  Proj.LoadFromFile(d + '/eliah.pxxproj');
end;

procedure TEliahForm.OnTreeClick(Sender: TObject);
var idx: Integer; b: TIdeBuffer;
begin
  idx := Tree.ItemIndex;
  if (idx < 0) or (idx >= nItems) then Exit;
  if isdirs[idx] then
  begin
    LoadDir(paths[idx]);
    Exit;
  end;
  curFile := paths[idx];
  b := TIdeBuffer.Create;
  if not b.LoadFromFile(curFile) then
    Editor.Text := '(could not open ' + curFile + ')'
  else if LooksBinary(b.Text) then
    { soft-guard: don't dump a binary into the editor (garbled + slow). Show a
      hex preview of the head instead, and skip the designer load. }
    Editor.Text := '[binary file: ' + curFile + '  (' +
      IntToStr(Length(b.Text)) + ' bytes)]' + #10 + #10 +
      HexPreview(b.Text, 2048)
  else
  begin
    Editor.Text := b.Text;
    { a .lfm also loads into the designer surface }
    if EndsWithLfm(curFile) then OpenDesign(curFile);
  end;
end;

{ click a diagnostic -> jump the editor to its line (compiler lines are 1-based,
  the memo caret is 0-based) }
procedure TEliahForm.OnErrorClick(Sender: TObject);
var idx, line: Integer;
begin
  idx := Errors.ItemIndex;
  if (idx < 0) or (idx >= Diags.Count) then Exit;
  line := Diags.DiagLine(idx);
  if line > 0 then Editor.CaretToLine(line - 1);
end;

{ start a blank design: a single root form. Save will prompt to a fresh path
  (untitled.lfm) so it never clobbers the previously-open file. }
procedure TEliahForm.OnNew(Sender: TObject);
var d: TDocModel;
begin
  d := TDocModel.Create;
  d.AddNode(wkForm, 'EliahForm', -1, 12, 12, 320, 240);
  Dsn.Doc := d;
  if Sel <> nil then Sel.SetDoc(d);
  Dsn.Sel := -1;
  Dsn.EndDrag;
  designPath := 'untitled.lfm';
  if DesignBox <> nil then DesignBox.Invalidate;
  ShowInspector(-1);
  Output.Text := '$ new design (untitled.lfm)';
end;

{ delete the selected node (and its children); the root form is kept }
procedure TEliahForm.OnDelete(Sender: TObject);
begin
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  if Dsn.Sel <= 0 then Exit;   { -1 none, 0 = root form (not deletable) }
  PushUndo(SaveLfmText(Dsn.Doc));
  Dsn.Doc.DeleteNode(Dsn.Sel);
  Dsn.Sel := -1;
  Dsn.EndDrag;
  DesignBox.Invalidate;
  ShowInspector(-1);
end;

{ load a .lfm into a fresh designer docmodel and make it the save target }
procedure TEliahForm.OpenDesign(const path: AnsiString);
var b: TIdeBuffer; d: TDocModel;
begin
  b := TIdeBuffer.Create;
  if not b.LoadFromFile(path) then
  begin
    Output.Text := '$ open design failed: ' + path;
    Exit;
  end;
  d := TDocModel.Create;
  if LoadLfmText(b.Text, d) then
  begin
    Dsn.Doc := d;
    if Sel <> nil then Sel.SetDoc(d);
    Dsn.Sel := -1;
    Dsn.EndDrag;
    designPath := path;
    if DesignBox <> nil then DesignBox.Invalidate;
    ShowInspector(-1);
    Output.Text := '$ opened design ' + path + ' (' + IntToStr(d.Count) + ' nodes)';
  end
  else
    Output.Text := '$ no objects in ' + path;
end;

procedure TEliahForm.OnCompile(Sender: TObject);
var out, lbl: AnsiString; rc, i: Integer; args: TStrArray;
begin
  { a loaded project (eliah.pxxproj) drives the build; otherwise compile the
    single open file straight to BUILD_OUT. }
  if (Proj <> nil) and (Proj.MainUnit <> '') then
  begin
    args := Proj.BuildArgs;
    lbl := Proj.MainUnit + ' (project ' + Proj.Name + ')';
  end
  else if curFile <> '' then
  begin
    SetLength(args, 2);
    args[0] := curFile;
    args[1] := BUILD_OUT;
    lbl := curFile;
  end
  else begin Output.Text := '(no file selected)'; Exit; end;
  out := RunCapture(PXX_PATH, args, rc);
  Output.Text := '$ compile ' + lbl + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
  { parse diagnostics into the clickable error list }
  Diags.Clear;
  Diags.Parse(out);
  Errors.Clear;
  if Diags.Count = 0 then
    Errors.AddItem('(no diagnostics)')
  else
    for i := 0 to Diags.Count - 1 do
      Errors.AddItem('L' + IntToStr(Diags.DiagLine(i)) + ': ' + Diags.DiagMsg(i));
end;

procedure TEliahForm.OnRun(Sender: TObject);
var out, exe: AnsiString; rc: Integer;
begin
  { run the project's output binary when a project defines one, else BUILD_OUT }
  if (Proj <> nil) and (Proj.MainUnit <> '') and (Proj.OutPath <> '') then
    exe := Proj.OutPath
  else
    exe := BUILD_OUT;
  out := RunCapture(exe, [], rc);
  Output.Text := '$ run ' + exe + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
end;

procedure TEliahForm.OnUp(Sender: TObject);
begin
  LoadDir(ParentDir(dir));
end;

{ File -> Open Folder: pick a directory and make it the project tree root }
procedure TEliahForm.OnOpenFolder(Sender: TObject);
var p: AnsiString;
begin
  p := SelectFolderDialog('Open Project Folder');
  if p <> '' then LoadDir(p);
end;

procedure TEliahForm.OnExit(Sender: TObject);
begin
  Halt(0);
end;

{ File->Examples->X : the menu item's caption is the example file name; open it
  (loads into the editor, and the designer too when it is a .lfm). }
procedure TEliahForm.OnExampleClick(Sender: TObject);
var nm, path: AnsiString; b: TIdeBuffer;
begin
  if Sender = nil then Exit;
  nm := TMenuItem(Sender).Caption;
  path := EXAMPLES_DIR + '/' + nm;
  b := TIdeBuffer.Create;
  if not b.LoadFromFile(path) then
  begin Output.Text := '$ no example: ' + path; Exit; end;
  curFile := path;
  Editor.Text := b.Text;
  if EndsWithLfm(path) then OpenDesign(path);
  Output.Text := '$ opened example ' + nm;
end;

{ reflow for a content area of w x h. The pane layout is the RootPaned subtree —
  GtkPaned owns the internal splits, so we only resize the root to fill the area
  below the toolbar. Toolbar widgets stay pinned at the top. }
procedure TEliahForm.Relayout(w, h: Integer);
var contentH: Integer;
begin
  contentH := h - TOOLBAR_H;
  if contentH < 160 then contentH := 160;
  if RootPaned <> nil then
    RootPaned.SetBounds(0, TOOLBAR_H, w, contentH);
  if DesignBox <> nil then DesignBox.Invalidate;
end;

{ Set a paned to one of three states without flicker: 0=show both, 1=collapse
  pane1, 2=collapse pane2. Idempotent (no-op if already in that state). }
procedure SetPanedVis(p: TPaned; show1, show2: Boolean);
var desired: Integer;
begin
  if p = nil then Exit;
  if show1 and show2 then desired := 0
  else if show1 then desired := 2          { second pane hidden }
  else desired := 1;                        { first pane hidden (or both: keep 1) }
  if p.CollapsedPane = desired then Exit;
  if desired = 0 then p.Restore
  else p.Collapse(desired, 0);
end;

{ The whole horizontal layout is the perspective model applied to the splitter
  tree. RootPaned = [ left | midRight ]; midRight = [ center | right ]. Compact
  for the current width (auto-collapse the lowest-priority column when the
  minimums don't fit), then map each column's shown-state onto its splitter.
  Pure layout — no mode branching. }
procedure TEliahForm.ApplyLayout(w: Integer);
var sLeft, sCenter, sRight: Boolean;
begin
  if (Persp = nil) or (RootPaned = nil) or (midRight = nil) then Exit;
  Persp.Compact(w);
  sLeft   := Persp.IsShown(Persp.IndexOf('left'));
  sCenter := Persp.IsShown(Persp.IndexOf('center'));
  sRight  := Persp.IsShown(Persp.IndexOf('right'));
  SetPanedVis(midRight, sCenter, sRight);
  SetPanedVis(RootPaned, sLeft, True);     { the right side is always the midRight container }
end;

{ Perspectives set per-column visibility choices, then re-apply the layout.
    code   -> hide right   (editor focus)
    design -> hide center  (designer focus)
    split  -> show all     (large monitor / full) }
procedure TEliahForm.SetPerspective(const name: AnsiString);
begin
  if Persp = nil then Exit;
  Persp.SetVisible(Persp.IndexOf('left'),   True);
  Persp.SetVisible(Persp.IndexOf('center'), name <> 'design');
  Persp.SetVisible(Persp.IndexOf('right'),  name <> 'code');
  if lastW > 0 then ApplyLayout(lastW);
end;

procedure TEliahForm.OnPerspCode(Sender: TObject);   begin SetPerspective('code');   end;
procedure TEliahForm.OnPerspDesign(Sender: TObject); begin SetPerspective('design'); end;
procedure TEliahForm.OnPerspSplit(Sender: TObject);  begin SetPerspective('split');  end;

{ View-menu toggles flip a column's visibility choice, then re-apply. }
{ header buttons show a chevron that flips with collapse state: v = shown
  (click to collapse), > = collapsed (click to restore). }
procedure SetHdrChevron(btn: TButton; const title: AnsiString; shown: Boolean);
begin
  if btn = nil then Exit;
  if shown then btn.Caption := 'v ' + title
  else btn.Caption := '> ' + title;
end;

procedure TEliahForm.OnToggleLeft(Sender: TObject);
var i: Integer; shown: Boolean;
begin
  if Persp = nil then Exit;
  i := Persp.IndexOf('left');
  shown := not Persp.PaneVisible(i);
  Persp.SetVisible(i, shown);
  if lastW > 0 then ApplyLayout(lastW);
  SetHdrChevron(leftHdr, 'Project', shown);
end;

procedure TEliahForm.OnToggleRight(Sender: TObject);
var i: Integer; shown: Boolean;
begin
  if Persp = nil then Exit;
  i := Persp.IndexOf('right');
  shown := not Persp.PaneVisible(i);
  Persp.SetVisible(i, shown);
  if lastW > 0 then ApplyLayout(lastW);
  SetHdrChevron(rightHdr, 'Designer', shown);
end;

procedure TEliahForm.OnToggleOutput(Sender: TObject);
begin
  if colCenter = nil then Exit;
  colCenter.Toggle(2, 0);    { vertical sub-pane: build/run output }
  SetHdrChevron(outputHdr, 'Output', colCenter.CollapsedPane <> 2);
end;

procedure TEliahForm.OnFormResize(Sender: TControl; w, h: Integer);
var contentH: Integer;
begin
  { only react to a real width change; the GtkFixed's size-allocate otherwise
    feeds back on its own child sizes and walks the height up endlessly. }
  if w = lastW then Exit;
  lastW := w;
  Relayout(w, h);

  { Seed the splitter handles once, on the first real allocation — GtkPaned
    clamps a position set before it has a size, so doing it at construction
    silently fails. Seed only once so later user drags are not reset. }
  if (not panedSeeded) and (w > 0) and (RootPaned <> nil) then
  begin
    contentH := h - TOOLBAR_H;
    RootPaned.Position    := W_TREE;             { left column width }
    midRight.Position     := w - W_TREE - W_RIGHT;{ center column width }
    colLeft.Position      := contentH - ERR_H;    { tree above errors }
    colCenter.Position    := contentH - H_BOTTOM; { editor above output }
    colRight.Position     := contentH - H_BOTTOM; { designer above inspector }
    colInspector.Position := H_BOTTOM - 28;       { props above value edit }
    panedSeeded := True;
    { apply a startup perspective once the panes have a real allocation }
    if startPersp <> '' then SetPerspective(startPersp)
    else ApplyLayout(w);
  end
  else
    { later resizes: re-run priority compacting (auto-collapse on shrink) }
    ApplyLayout(w);
end;

{ serialize the designer docmodel back to the open design file (round-trips the
  loader); falls back to the sample if nothing was opened explicitly }
procedure TEliahForm.OnSave(Sender: TObject);
var target: AnsiString;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  if designPath <> '' then target := designPath else target := SAMPLE_LFM;
  if WriteAllText(target, SaveLfmText(Dsn.Doc)) then
    Output.Text := '$ saved ' + target + ' (' + IntToStr(Dsn.Doc.Count) + ' nodes)'
  else
    Output.Text := '$ save failed: ' + target;
  UpdateTitle;
end;

{ status line in the window title: open file, node count, current selection }
procedure TEliahForm.UpdateTitle;
var s: AnsiString;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  s := 'Eliah - ' + designPath + ' (' + IntToStr(Dsn.Doc.Count) + ' nodes)';
  if (Dsn.Sel >= 0) and (Dsn.Sel < Dsn.Doc.Count) then
    s := s + '  [sel: ' + Dsn.Doc.KindName(Dsn.Doc.NodeKind(Dsn.Sel)) +
         ' ' + Dsn.Doc.NodeCaption(Dsn.Sel) + ']';
  Self.Caption := s;
end;

{ stream the window chrome from eliah.lfm (publishes bind widgets + events) }
constructor TEliahForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Self.HandleNeeded;
  InitInheritedComponent(Self, 'TEliahForm');
end;

{ the designer paint-box's OnPaint (bound from the .lfm) delegates to the designer }
procedure TEliahForm.OnDesignPaint(Sender: TControl; Canvas: TCanvas);
begin
  if Dsn <> nil then Dsn.Paint(Sender, Canvas);
end;

{ append one extra-property row (name + current bag value), recording the name so
  the click/apply handlers can map the row back to the property. }
procedure TEliahForm.AddBagRow(d: TDocModel; idx: Integer; const nm: AnsiString);
var n: Integer;
begin
  if FBagBase = 0 then FBagBase := Props.Count;   { first extra row }
  n := Length(FBagNames);
  SetLength(FBagNames, n + 1);
  FBagNames[n] := nm;
  Props.AddItem(nm + ' = ' + d.NodePropByName(idx, nm));
end;

function TEliahForm.BagRowShown(const nm: AnsiString): Boolean;
var k: Integer;
begin
  BagRowShown := False;
  for k := 0 to Length(FBagNames) - 1 do
    if FBagNames[k] = nm then begin BagRowShown := True; Exit; end;
end;

{ Route a selection through the shared model and refresh the designer + inspector.
  Does NOT touch the editor — call EditorToSelection for the designer->editor jump
  (kept separate so editor->designer doesn't loop back). }
procedure TEliahForm.SelectNode(idx: Integer);
begin
  if Sel <> nil then Sel.Select(idx);
  if Dsn <> nil then
  begin
    if Sel <> nil then Dsn.Sel := Sel.Selected else Dsn.Sel := idx;
    if DesignBox <> nil then DesignBox.Invalidate;
    ShowInspector(Dsn.Sel);
  end;
end;

{ designer -> editor: show the design's .lfm and scroll to the selected node's
  `object <Name>` declaration. }
procedure TEliahForm.EditorToSelection;
var nm: AnsiString; ln: Integer; eb: TIdeBuffer;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) or (Editor = nil) then Exit;
  nm := Dsn.Doc.NodeName(Dsn.Sel);
  if nm = '' then Exit;
  { make the editor show the design file (the one the designer renders) }
  if (curFile <> designPath) and (designPath <> '') then
  begin
    eb := TIdeBuffer.Create;
    if eb.LoadFromFile(designPath) then
    begin
      Editor.Text := eb.Text;
      curFile := designPath;
    end;
  end;
  ln := LfmFindObjectLine(Editor.Text, nm);
  if ln >= 0 then Editor.CaretToLine(ln);
end;

{ editor -> designer: the component declared on editor line `ln` becomes the
  selection (no editor scroll-back — the caret is already there). }
procedure TEliahForm.SelectFromEditorLine(ln: Integer);
var nm: AnsiString; idx: Integer;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Editor = nil) then Exit;
  nm := LfmObjectNameAt(Editor.Text, ln);
  if nm = '' then Exit;
  idx := Dsn.Doc.FindByName(nm);
  if idx >= 0 then SelectNode(idx);
end;

procedure TEliahForm.OnPickFromCaret(Sender: TObject);
begin
  if Editor <> nil then SelectFromEditorLine(Editor.CaretLine);
end;

{ command: wire the selected component's OnClick — assign a handler (round-trips
  in the .lfm, shows in the inspector) and generate its stub in the code editor.
  One command on the shared selection; a menu/shortcut/AI source is interchangeable. }
procedure TEliahForm.OnWireOnClick(Sender: TObject);
var nm, hn: AnsiString;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) then Exit;
  nm := Dsn.Doc.NodeName(Dsn.Sel);
  if nm = '' then Exit;
  hn := EventHandlerName(nm, 'Click');
  PushUndo(SaveLfmText(Dsn.Doc));
  Dsn.Doc.SetNodeProp(Dsn.Sel, 'OnClick', hn);     { assignment }
  if (Editor <> nil) and not CodeHasHandler(Editor.Text, hn) then
  begin
    Editor.Text := Editor.Text + #10 + EventHandlerStub(hn);   { stub }
    Editor.CaretToLine(100000);                    { scroll to the new stub (gtk clamps) }
  end;
  ShowInspector(Dsn.Sel);
  if DesignBox <> nil then DesignBox.Invalidate;
  Output.Text := '$ wired ' + nm + '.OnClick -> ' + hn;
end;

procedure TEliahForm.ShowInspector(idx: Integer);
var
  d: TDocModel; j, cnt: Integer;
  cls: PClassRTTI;
  plist: TPropList;
  nm: AnsiString;
begin
  UpdateTitle;
  Props.Clear;
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  d := Dsn.Doc;
  if (idx < 0) or (idx >= d.Count) then
  begin
    Props.AddItem('(no selection)');
    Exit;
  end;
  Props.AddItem('Kind:    ' + d.KindName(d.NodeKind(idx)));
  Props.AddItem('Caption: ' + d.NodeCaption(idx));
  if d.IsNonVisual(d.NodeKind(idx)) then
    { non-visual components have no canvas geometry — they sit in the tray. }
    Props.AddItem('(non-visual: tray component)')
  else
  begin
    Props.AddItem('Left:    ' + IntToStr(d.NodeX(idx)));
    Props.AddItem('Top:     ' + IntToStr(d.NodeY(idx)));
    Props.AddItem('Width:   ' + IntToStr(d.NodeW(idx)));
    Props.AddItem('Height:  ' + IntToStr(d.NodeH(idx)));
  end;
  { extra published properties — driven by the registered class's RTTI so EVERY
    published data property shows (Interval, Enabled, …), even ones not yet in the
    .lfm; the value comes from the node's bag (blank if unset). Editing writes the
    bag. Events (method props) are skipped — they belong to the wiring surface. }
  FBagBase := 0;
  SetLength(FBagNames, 0);
  cls := GetClass('T' + d.KindName(d.NodeKind(idx)));
  if cls <> nil then
  begin
    cnt := GetPropList(cls, @plist);
    for j := 0 to cnt - 1 do
    begin
      nm := PropName(plist[j]);
      if (plist[j]^.Kind = 5) or IsModelledProp(nm) or BagRowShown(nm) then Continue;
      AddBagRow(d, idx, nm);
    end;
  end;
  { also surface any stored prop the class RTTI didn't list (orphan / unknown) }
  for j := 0 to d.NodePropCount(idx) - 1 do
  begin
    nm := d.NodePropName(idx, j);
    if not BagRowShown(nm) then AddBagRow(d, idx, nm);
  end;
end;

{ undo stack holds .lfm snapshots (SaveLfmText round-trips losslessly) }
procedure TEliahForm.PushUndo(const snap: AnsiString);
begin
  SetLength(undoStack, undoCount + 1);
  undoStack[undoCount] := snap;
  Inc(undoCount);
end;

procedure TEliahForm.OnUndo(Sender: TObject);
var d: TDocModel; ok: Boolean;
begin
  if undoCount <= 0 then begin Output.Text := '$ nothing to undo'; Exit; end;
  Dec(undoCount);
  d := TDocModel.Create;
  ok := LoadLfmText(undoStack[undoCount], d);
  Dsn.Doc := d;
  if Sel <> nil then Sel.SetDoc(d);
  Dsn.Sel := -1;
  Dsn.EndDrag;
  if DesignBox <> nil then DesignBox.Invalidate;
  ShowInspector(-1);
  Output.Text := '$ undo (' + IntToStr(undoCount) + ' left)';
end;

procedure TEliahForm.OnPlaceToggle(Sender: TObject);
begin
  PlaceMode := not PlaceMode;
  if PlaceMode then PlaceBtn.Caption := 'Place*' else PlaceBtn.Caption := 'Place';
end;

{ A component-bar button: select its palette row and make sure Place is armed
  (sticky, same as arming via the Place button). }
procedure TEliahForm.OnPaletteButton(Sender: TButton);
var i: Integer;
begin
  for i := 0 to Length(BarButtons) - 1 do
    if Pointer(BarButtons[i]) = Pointer(Sender) then
    begin
      Palette.ItemIndex := BarRows[i];
      if not PlaceMode then OnPlaceToggle(nil);
      Exit;
    end;
end;

procedure TEliahForm.OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
var idx: Integer; k: TWidgetKind;
begin
  { snapshot the pre-action state; committed to undo only if the doc changes }
  pendingSnap := SaveLfmText(Dsn.Doc);
  if PlaceMode then
  begin
    { resolve the palette selection to a placeable kind; a group-divider row
      (empty class name) or anything CompPlaceKind rejects just disarms. }
    if (Palette.ItemIndex < 0) or (Palette.ItemIndex >= Length(PaletteNames)) or
       not CompPlaceKind(PaletteNames[Palette.ItemIndex], k) then
    begin
      OnPlaceToggle(nil);
      Exit;
    end;
    { drop a new widget of the palette kind, parented to the form (node 0).
      Place is STICKY: stays armed so several widgets can be dropped in a row;
      click Place again (or pick another tool) to stop. }
    PushUndo(pendingSnap);
    idx := Dsn.Doc.AddNode(k, Dsn.Doc.KindName(k), 0, X, Y, 80, 24);
    SelectNode(idx);
    Exit;
  end;
  idx := Dsn.BeginDrag(X, Y);
  { route through the shared selection model + jump the editor to the node's code }
  SelectNode(idx);
  EditorToSelection;
end;

procedure TEliahForm.OnDesignMouseMove(Sender: TControl; Button, X, Y: Integer);
begin
  if not (Dsn.Dragging or Dsn.Resizing) then Exit;
  Dsn.DragTo(X, Y);
  DesignBox.Invalidate;
  ShowInspector(Dsn.Sel);
end;

procedure TEliahForm.OnDesignMouseUp(Sender: TControl; Button, X, Y: Integer);
begin
  Dsn.EndDrag;
  { commit the pre-drag snapshot only if a move/resize actually changed the doc }
  if (pendingSnap <> '') and (SaveLfmText(Dsn.Doc) <> pendingSnap) then
    PushUndo(pendingSnap);
  pendingSnap := '';
  ShowInspector(Dsn.Sel);
end;

{ click an inspector row -> load that field's current value into the edit }
procedure TEliahForm.OnPropClick(Sender: TObject);
var d: TDocModel;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) then Exit;
  d := Dsn.Doc;
  FEditRow := Props.ItemIndex;
  { a bag row (extra published prop): edit its value }
  if (FBagBase > 0) and (FEditRow >= FBagBase) and
     (FEditRow - FBagBase < Length(FBagNames)) then
  begin
    ValueEdit.Text := d.NodePropByName(Dsn.Sel, FBagNames[FEditRow - FBagBase]);
    Exit;
  end;
  { non-visual nodes only expose an editable Caption (no geometry rows) }
  if d.IsNonVisual(d.NodeKind(Dsn.Sel)) then
  begin
    if FEditRow = 1 then ValueEdit.Text := d.NodeCaption(Dsn.Sel)
    else ValueEdit.Text := '';
    Exit;
  end;
  case FEditRow of
    1: ValueEdit.Text := d.NodeCaption(Dsn.Sel);
    2: ValueEdit.Text := IntToStr(d.NodeX(Dsn.Sel));
    3: ValueEdit.Text := IntToStr(d.NodeY(Dsn.Sel));
    4: ValueEdit.Text := IntToStr(d.NodeW(Dsn.Sel));
    5: ValueEdit.Text := IntToStr(d.NodeH(Dsn.Sel));
  else
    ValueEdit.Text := '';   { Kind (0) and anything else: not editable }
  end;
end;

{ Enter (Return / KP_Enter) in the value edit commits it to the docmodel }
procedure TEliahForm.OnValueKey(Sender: TControl; KeyCode: Integer);
begin
  if (KeyCode = 65293) or (KeyCode = 65421) then ApplyEdit;
end;

procedure TEliahForm.ApplyEdit;
var d: TDocModel; v: AnsiString;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) then Exit;
  d := Dsn.Doc;
  v := ValueEdit.Text;
  { a bag row: write the value back to the named extra property }
  if (FBagBase > 0) and (FEditRow >= FBagBase) and
     (FEditRow - FBagBase < Length(FBagNames)) then
  begin
    PushUndo(SaveLfmText(d));
    d.SetNodeProp(Dsn.Sel, FBagNames[FEditRow - FBagBase], v);
    DesignBox.Invalidate;
    ShowInspector(Dsn.Sel);
    Exit;
  end;
  { non-visual nodes: only Caption is editable (geometry is tray-derived) }
  if d.IsNonVisual(d.NodeKind(Dsn.Sel)) and (FEditRow <> 1) then Exit;
  PushUndo(SaveLfmText(d));
  case FEditRow of
    1: d.SetNodeCaption(Dsn.Sel, v);
    2: d.SetNodeBounds(Dsn.Sel, StrToIntDef(v, d.NodeX(Dsn.Sel)),
         d.NodeY(Dsn.Sel), d.NodeW(Dsn.Sel), d.NodeH(Dsn.Sel));
    3: d.SetNodeBounds(Dsn.Sel, d.NodeX(Dsn.Sel),
         StrToIntDef(v, d.NodeY(Dsn.Sel)), d.NodeW(Dsn.Sel), d.NodeH(Dsn.Sel));
    4: d.SetNodeBounds(Dsn.Sel, d.NodeX(Dsn.Sel), d.NodeY(Dsn.Sel),
         StrToIntDef(v, d.NodeW(Dsn.Sel)), d.NodeH(Dsn.Sel));
    5: d.SetNodeBounds(Dsn.Sel, d.NodeX(Dsn.Sel), d.NodeY(Dsn.Sel),
         d.NodeW(Dsn.Sel), StrToIntDef(v, d.NodeH(Dsn.Sel)));
  end;
  DesignBox.Invalidate;
  ShowInspector(Dsn.Sel);
end;

var
  EliahForm: TEliahForm;
  arg, startDir, parg: AnsiString;
  pix: Integer;
  centerW, centerH, contentH: Integer;
  sbuf: TIdeBuffer;
  sok: Boolean;
  rtdoc: TDocModel;
  MainMenu: TMainMenu;
  FileMenu, EditMenu, BuildMenu, ViewMenu, ExMenu, mi: TMenuItem;
  comps: TRegEntryArr;
  ci, nvFirst: Integer;
  pk: TWidgetKind;
  tabStd, tabNv, barTab: Integer;
  bb: TButton;
  exlist: TFileInfoArray;
  exi: Integer;

function MkMenuItem(const cap: AnsiString; parent: TMenuItem): TMenuItem;
var it: TMenuItem;
begin
  it := TMenuItem.Create(nil);
  it.Caption := cap;
  parent.Add(it);
  MkMenuItem := it;
end;

{ --gui-smoke: self-quit fired by g_timeout_add once the real event loop has
  been running (the window is mapped and painted by then). }
function GuiAutoQuit(data: Pointer): Integer; cdecl;
begin
  gtk_main_quit;
  GuiAutoQuit := 0;   { one-shot: remove the source }
end;

begin
  Application := TApplication.Create;
  Application.Initialize;

  contentH := H_WIN - TOOLBAR_H;
  centerW := W_WIN - W_TREE - W_RIGHT;
  centerH := contentH - H_BOTTOM;

  { stream the whole window chrome (toolbar + nested-TPaned splitter tree + leaf
    widgets) from eliah.lfm. Published fields/methods on TEliahForm bind the
    widgets and the OnX handlers. Pane tree:
        RootPaned(H) = colLeft(V: Tree/Errors) | midRight(H) =
          colCenter(V: Editor/Output) | colRight(V: DesignBox | colInspector(V: Props/ValueEdit)) }
  EliahForm := TEliahForm.Create(nil);
  EliahForm.SetBounds(0, 0, W_WIN, H_WIN);
  EliahForm.Proj := TProject.Create;
  EliahForm.panedSeeded := False;
  EliahForm.FEditRow := -1;
  EliahForm.lastW := -1;
  EliahForm.designPath := SAMPLE_LFM;   { Save targets the sample until a .lfm is opened }

  { compacting priorities for the three columns (higher survives a shrink longer) }
  EliahForm.Persp := TPerspective.Create;
  EliahForm.Persp.SetName('Split');
  EliahForm.Persp.AddPane('left',   W_TREE,  50, True);
  EliahForm.Persp.AddPane('center', 320,     90, True);
  EliahForm.Persp.AddPane('right',  W_RIGHT, 40, True);

  EliahForm.Diags := TDiagList.Create;

  { designer: box-emulated preview from the garin docmodel. Seed it by loading the
    sample .lfm via the garin loader (box-emulation parser, NOT this live streamer).
    Create before Realize so the bound OnDesignPaint has a designer. }
  EliahForm.Dsn := TDesigner.Create;
  EliahForm.Dsn.Doc := TDocModel.Create;
  sbuf := TIdeBuffer.Create;
  if sbuf.LoadFromFile(SAMPLE_LFM) then
    sok := LoadLfmText(sbuf.Text, EliahForm.Dsn.Doc);
  EliahForm.Sel := TSelectionModel.Create(EliahForm.Dsn.Doc);

  EliahForm.Output.Text := 'build output appears here';
  EliahForm.Props.AddItem('object inspector (M1)');
  EliahForm.OnResize := @EliahForm.OnFormResize;

  { main menu bar (kept in code) }
  MainMenu := TMainMenu.Create(nil);
  EliahForm.Menu := MainMenu;

  FileMenu := TMenuItem.Create(nil); FileMenu.Caption := '&File'; MainMenu.Items.Add(FileMenu);
  mi := MkMenuItem('&New',          FileMenu); mi.OnClick := @EliahForm.OnNew;
  mi := MkMenuItem('&Open Folder...', FileMenu); mi.OnClick := @EliahForm.OnOpenFolder;
  mi := MkMenuItem('&Save',         FileMenu); mi.OnClick := @EliahForm.OnSave;

  { Examples submenu — autofilled from EXAMPLES_DIR (Arduino-style). Each item's
    caption is the example file name; OnExampleClick opens it. }
  ExMenu := TMenuItem.Create(nil); ExMenu.Caption := 'E&xamples'; FileMenu.Add(ExMenu);
  if GetDirectoryContents(EXAMPLES_DIR, exlist) then
    for exi := 0 to Length(exlist) - 1 do
      if (not exlist[exi].IsDir) and EndsWithLfm(exlist[exi].Name) then
      begin
        mi := MkMenuItem(exlist[exi].Name, ExMenu);
        mi.OnClick := @EliahForm.OnExampleClick;
      end;

  mi := MkMenuItem('E&xit',         FileMenu); mi.OnClick := @EliahForm.OnExit;

  EditMenu := TMenuItem.Create(nil); EditMenu.Caption := '&Edit'; MainMenu.Items.Add(EditMenu);
  mi := MkMenuItem('&Undo',   EditMenu); mi.OnClick := @EliahForm.OnUndo;
  mi := MkMenuItem('&Delete', EditMenu); mi.OnClick := @EliahForm.OnDelete;

  BuildMenu := TMenuItem.Create(nil); BuildMenu.Caption := '&Build'; MainMenu.Items.Add(BuildMenu);
  mi := MkMenuItem('&Compile', BuildMenu); mi.OnClick := @EliahForm.OnCompile;
  mi := MkMenuItem('&Run',     BuildMenu); mi.OnClick := @EliahForm.OnRun;

  ViewMenu := TMenuItem.Create(nil); ViewMenu.Caption := '&View'; MainMenu.Items.Add(ViewMenu);
  mi := MkMenuItem('&Code Layout',   ViewMenu); mi.OnClick := @EliahForm.OnPerspCode;
  mi := MkMenuItem('&Design Layout', ViewMenu); mi.OnClick := @EliahForm.OnPerspDesign;
  mi := MkMenuItem('&Split Layout',  ViewMenu); mi.OnClick := @EliahForm.OnPerspSplit;
  mi := MkMenuItem('Toggle &Left Panel',  ViewMenu); mi.OnClick := @EliahForm.OnToggleLeft;
  mi := MkMenuItem('Toggle &Output',      ViewMenu); mi.OnClick := @EliahForm.OnToggleOutput;
  mi := MkMenuItem('Toggle &Right Panel', ViewMenu); mi.OnClick := @EliahForm.OnToggleRight;

  { registry-driven palette: visual components first, a divider, then non-visual }
  comps := EnumDescendants('TComponent', False);
  SetLength(EliahForm.PaletteNames, 0);
  for ci := 0 to Length(comps) - 1 do
    if CompPlaceKind(comps[ci].Name, pk) and
       ClassDescendsFrom(comps[ci].Cls, 'TControl') then
    begin
      EliahForm.Palette.AddItem(CompDisplay(comps[ci].Name));
      SetLength(EliahForm.PaletteNames, Length(EliahForm.PaletteNames) + 1);
      EliahForm.PaletteNames[Length(EliahForm.PaletteNames) - 1] := comps[ci].Name;
    end;
  nvFirst := Length(EliahForm.PaletteNames);
  for ci := 0 to Length(comps) - 1 do
    if CompPlaceKind(comps[ci].Name, pk) and
       not ClassDescendsFrom(comps[ci].Cls, 'TControl') then
    begin
      if Length(EliahForm.PaletteNames) = nvFirst then
      begin
        EliahForm.Palette.AddItem('-- non-visual --');
        SetLength(EliahForm.PaletteNames, Length(EliahForm.PaletteNames) + 1);
        EliahForm.PaletteNames[Length(EliahForm.PaletteNames) - 1] := '';
      end;
      EliahForm.Palette.AddItem(CompDisplay(comps[ci].Name));
      SetLength(EliahForm.PaletteNames, Length(EliahForm.PaletteNames) + 1);
      EliahForm.PaletteNames[Length(EliahForm.PaletteNames) - 1] := comps[ci].Name;
    end;
  EliahForm.Palette.ItemIndex := 0;
  EliahForm.PlaceMode := False;

  { tabbed component bar under the button row — same registry enumeration as
    the combo, grouped visual / non-visual; short 3-char placeholder captions
    until per-component glyphs exist. Clicking arms Place for that component. }
  EliahForm.CompBar := TTabBar.Create(nil);
  EliahForm.CompBar.Parent := EliahForm;
  EliahForm.CompBar.SetBounds(0, 36, W_WIN, TOOLBAR_H - 40);
  tabStd := EliahForm.CompBar.AddTab('Standard');
  tabNv := EliahForm.CompBar.AddTab('Non-visual');
  SetLength(EliahForm.BarButtons, 0);
  SetLength(EliahForm.BarRows, 0);
  for ci := 0 to Length(EliahForm.PaletteNames) - 1 do
  begin
    if EliahForm.PaletteNames[ci] = '' then continue;   { the divider row }
    if ci < nvFirst then barTab := tabStd else barTab := tabNv;
    bb := EliahForm.CompBar.AddButton(barTab,
      Copy(CompDisplay(EliahForm.PaletteNames[ci]), 1, 3), @EliahForm.OnPaletteButton);
    if bb <> nil then
    begin
      SetLength(EliahForm.BarButtons, Length(EliahForm.BarButtons) + 1);
      EliahForm.BarButtons[Length(EliahForm.BarButtons) - 1] := bb;
      SetLength(EliahForm.BarRows, Length(EliahForm.BarRows) + 1);
      EliahForm.BarRows[Length(EliahForm.BarRows) - 1] := ci;
    end;
  end;

  arg := '';
  startDir := EXAMPLES_DIR;   { open the demo projects by default (override with a dir arg) }
  EliahForm.startPersp := '';
  for pix := 1 to ParamCount do
  begin
    parg := ParamStr(pix);
    if parg = '--smoke' then arg := '--smoke'
    else if parg = '--gui-smoke' then arg := '--gui-smoke'
    else if parg = '--code' then EliahForm.startPersp := 'code'
    else if parg = '--design' then EliahForm.startPersp := 'design'
    else if parg = '--split' then EliahForm.startPersp := 'split'
    else if (Length(parg) >= 2) and (parg[1] = '-') and (parg[2] = '-') then
      { ignore unknown -- flag }
    else
      startDir := parg;                 { a bare argument is the start directory }
  end;
  EliahForm.LoadDir(startDir);

  EliahForm.Realize;

  if arg = '--smoke' then
  begin
    if EliahForm.nItems < 1 then begin writeln('SMOKE FAIL: empty tree'); Halt(1); end;

    { sample .lfm loaded into the designer docmodel }
    if EliahForm.Dsn.Doc.Count <> 6 then begin writeln('SMOKE FAIL: sample.lfm not loaded'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeCaption(3) <> 'OK' then begin writeln('SMOKE FAIL: lfm OK button missing'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeX(3) <> 28 then begin writeln('SMOKE FAIL: lfm abs coord wrong'); Halt(1); end;
    { the sample's TTimer streams in as a non-visual tray node }
    if not EliahForm.Dsn.Doc.IsNonVisual(EliahForm.Dsn.Doc.NodeKind(5)) then
      begin writeln('SMOKE FAIL: sample TTimer not a non-visual node'); Halt(1); end;

    { pane layout is the RootPaned subtree; reflow resizes the root to fill the
      content area below the toolbar (GtkPaned owns the internal splits). }
    if EliahForm.RootPaned = nil then begin writeln('SMOKE FAIL: no root paned'); Halt(1); end;
    EliahForm.Relayout(1400, 900);
    if EliahForm.RootPaned.Width <> 1400 then begin writeln('SMOKE FAIL: root paned width did not reflow'); Halt(1); end;
    if EliahForm.RootPaned.Height <> (900 - TOOLBAR_H) then begin writeln('SMOKE FAIL: root paned height did not reflow'); Halt(1); end;
    { tiny window clamps the content height instead of going negative }
    EliahForm.Relayout(200, 120);
    if EliahForm.RootPaned.Height < 160 then begin writeln('SMOKE FAIL: reflow did not clamp height'); Halt(1); end;
    EliahForm.Relayout(W_WIN, H_WIN);   { restore }

    { headless has no real allocation, so drive layout with an explicit width.
      View-menu toggle flips the left column's visibility choice. }
    EliahForm.OnToggleLeft(nil); EliahForm.ApplyLayout(W_WIN);
    if EliahForm.RootPaned.CollapsedPane <> 1 then begin writeln('SMOKE FAIL: left panel did not collapse'); Halt(1); end;
    EliahForm.OnToggleLeft(nil); EliahForm.ApplyLayout(W_WIN);
    if EliahForm.RootPaned.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: left panel did not restore'); Halt(1); end;

    { perspectives are visibility configs of midRight = [center | right] }
    EliahForm.SetPerspective('code'); EliahForm.ApplyLayout(W_WIN);
    if EliahForm.midRight.CollapsedPane <> 2 then begin writeln('SMOKE FAIL: code persp did not hide right'); Halt(1); end;
    EliahForm.SetPerspective('design'); EliahForm.ApplyLayout(W_WIN);
    if EliahForm.midRight.CollapsedPane <> 1 then begin writeln('SMOKE FAIL: design persp did not hide center'); Halt(1); end;
    EliahForm.SetPerspective('split'); EliahForm.ApplyLayout(W_WIN);
    if EliahForm.midRight.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: split persp did not show both'); Halt(1); end;

    { priority compacting: a width below sum(mins) auto-collapses the lowest
      priority column (right=designer), even in the split perspective. }
    EliahForm.SetPerspective('split'); EliahForm.ApplyLayout(400);
    if EliahForm.midRight.CollapsedPane <> 2 then begin writeln('SMOKE FAIL: compacting did not drop right'); Halt(1); end;
    EliahForm.ApplyLayout(W_WIN);
    if EliahForm.midRight.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: widening did not restore right'); Halt(1); end;

    { open any .lfm from the tree: clicking a .lfm reloads the designer + retargets Save }
    EliahForm.Dsn.Doc := TDocModel.Create;   { wipe to prove OpenDesign reloads }
    EliahForm.designPath := '';
    EliahForm.OpenDesign('apps/ide/eliah/sample.lfm');
    if EliahForm.Dsn.Doc.Count <> 6 then begin writeln('SMOKE FAIL: OpenDesign did not load'); Halt(1); end;
    if EliahForm.designPath <> 'apps/ide/eliah/sample.lfm' then begin writeln('SMOKE FAIL: designPath not set'); Halt(1); end;
    if not EndsWithLfm('Foo.LFM') then begin writeln('SMOKE FAIL: EndsWithLfm case'); Halt(1); end;
    if EndsWithLfm('foo.pas') then begin writeln('SMOKE FAIL: EndsWithLfm false-pos'); Halt(1); end;

    EliahForm.LoadDir('apps/ide/garin');
    EliahForm.Tree.ItemIndex := EliahForm.nItems - 1;
    EliahForm.OnTreeClick(nil);
    if Length(EliahForm.Editor.Text) = 0 then begin writeln('SMOKE FAIL: editor empty'); Halt(1); end;
    EliahForm.curFile := 'apps/ide/garin/buffer.pas';
    EliahForm.OnCompile(nil);
    if Length(EliahForm.Output.Text) = 0 then begin writeln('SMOKE FAIL: no compile output'); Halt(1); end;

    { diagnostics: compile a deliberately broken unit -> error list populated,
      click jumps the editor (no crash). }
    if not WriteAllText('/tmp/eliah_bad.pas', 'program bad;' + #10 + 'begin' + #10 + '  x := 1;' + #10 + 'end.' + #10) then
      begin writeln('SMOKE FAIL: could not write bad.pas'); Halt(1); end;
    EliahForm.curFile := '/tmp/eliah_bad.pas';
    EliahForm.OnCompile(nil);
    if EliahForm.Diags.Count < 1 then begin writeln('SMOKE FAIL: no diagnostics parsed'); Halt(1); end;
    if EliahForm.Diags.DiagLine(0) <> 3 then begin writeln('SMOKE FAIL: diag line wrong'); Halt(1); end;
    EliahForm.Errors.ItemIndex := 0;
    EliahForm.OnErrorClick(nil);   { jump to the error line — must not crash }

    { designer mouse-select: click inside the sample OK button (x=28..108,
      y=92..120) -> it must become the selection and fill the inspector. }
    EliahForm.OnDesignMouseDown(nil, 1, 40, 100);
    if EliahForm.Dsn.Sel < 0 then begin writeln('SMOKE FAIL: no node selected'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeCaption(EliahForm.Dsn.Sel) <> 'OK' then
      begin writeln('SMOKE FAIL: wrong node selected'); Halt(1); end;

    { drag-move: grab the OK button at (40,100) — origin (28,92), so the grab
      offset is (12,8) — and move the cursor to (70,140); the node origin must
      follow to (70-12, 140-8) = (58,132). }
    EliahForm.OnDesignMouseDown(nil, 1, 40, 100);
    EliahForm.OnDesignMouseMove(nil, 1, 70, 140);
    EliahForm.OnDesignMouseUp(nil, 1, 70, 140);
    if (EliahForm.Dsn.Doc.NodeX(EliahForm.Dsn.Sel) <> 58) or (EliahForm.Dsn.Doc.NodeY(EliahForm.Dsn.Sel) <> 132) then
      begin writeln('SMOKE FAIL: drag-move did not reposition node'); Halt(1); end;
    { move after release must NOT keep dragging }
    EliahForm.OnDesignMouseMove(nil, 0, 200, 200);
    if (EliahForm.Dsn.Doc.NodeX(EliahForm.Dsn.Sel) <> 58) then
      begin writeln('SMOKE FAIL: node moved after mouse-up'); Halt(1); end;

    { resize: OK button now at (58,132,80,28) -> BR corner at (138,160). Grab it
      and drag to (158,180): origin stays, W/H grow by 20 -> (58,132,100,48). }
    EliahForm.OnDesignMouseDown(nil, 1, 138, 160);
    if not EliahForm.Dsn.Resizing then begin writeln('SMOKE FAIL: handle did not start resize'); Halt(1); end;
    EliahForm.OnDesignMouseMove(nil, 1, 158, 180);
    EliahForm.OnDesignMouseUp(nil, 1, 158, 180);
    if (EliahForm.Dsn.Doc.NodeX(EliahForm.Dsn.Sel) <> 58) or (EliahForm.Dsn.Doc.NodeY(EliahForm.Dsn.Sel) <> 132) or
       (EliahForm.Dsn.Doc.NodeW(EliahForm.Dsn.Sel) <> 100) or (EliahForm.Dsn.Doc.NodeH(EliahForm.Dsn.Sel) <> 48) then
      begin writeln('SMOKE FAIL: BR resize wrong bounds'); Halt(1); end;

    { editable inspector: pick a row, type a value, commit -> docmodel updates }
    EliahForm.FEditRow := 1; EliahForm.ValueEdit.Text := 'Apply'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodeCaption(EliahForm.Dsn.Sel) <> 'Apply' then
      begin writeln('SMOKE FAIL: caption edit not applied'); Halt(1); end;
    EliahForm.FEditRow := 4; EliahForm.ValueEdit.Text := '120'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodeW(EliahForm.Dsn.Sel) <> 120 then
      begin writeln('SMOKE FAIL: width edit not applied'); Halt(1); end;
    { commit via the Enter key path (Return keyval) }
    EliahForm.FEditRow := 3; EliahForm.ValueEdit.Text := '200'; EliahForm.OnValueKey(nil, 65293);
    if EliahForm.Dsn.Doc.NodeY(EliahForm.Dsn.Sel) <> 200 then
      begin writeln('SMOKE FAIL: Enter did not commit Top edit'); Halt(1); end;
    { malformed int keeps the old value (StrToIntDef fallback) }
    EliahForm.FEditRow := 2; EliahForm.ValueEdit.Text := 'xyz'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodeX(EliahForm.Dsn.Sel) <> 58 then
      begin writeln('SMOKE FAIL: bad int should keep old Left'); Halt(1); end;

    { palette place: arm Place, click empty surface -> a new node is dropped,
      parented to the form, selected; Place is sticky (stays armed). }
    EliahForm.Palette.ItemIndex := 1;        { Label }
    EliahForm.OnPlaceToggle(nil);
    if not EliahForm.PlaceMode then begin writeln('SMOKE FAIL: place not armed'); Halt(1); end;
    centerW := EliahForm.Dsn.Doc.Count;      { reuse scratch int: node count before }
    EliahForm.OnDesignMouseDown(nil, 1, 150, 150);
    if EliahForm.Dsn.Doc.Count <> centerW + 1 then
      begin writeln('SMOKE FAIL: place did not add a node'); Halt(1); end;
    if EliahForm.Dsn.Sel <> centerW then
      begin writeln('SMOKE FAIL: placed node not selected'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeParent(EliahForm.Dsn.Sel) <> 0 then
      begin writeln('SMOKE FAIL: placed node not parented to form'); Halt(1); end;
    pk := wkButton;
    CompPlaceKind(EliahForm.PaletteNames[EliahForm.Palette.ItemIndex], pk);
    if EliahForm.Dsn.Doc.NodeKind(EliahForm.Dsn.Sel) <> pk then
      begin writeln('SMOKE FAIL: placed node wrong kind'); Halt(1); end;
    if Length(EliahForm.PaletteNames) < 7 then
      begin writeln('SMOKE FAIL: registry palette underpopulated'); Halt(1); end;
    { sticky: still armed, a second click drops another node without re-arming }
    if not EliahForm.PlaceMode then begin writeln('SMOKE FAIL: place not sticky'); Halt(1); end;
    centerW := EliahForm.Dsn.Doc.Count;
    EliahForm.OnDesignMouseDown(nil, 1, 200, 200);
    if EliahForm.Dsn.Doc.Count <> centerW + 1 then
      begin writeln('SMOKE FAIL: sticky place did not add a 2nd node'); Halt(1); end;
    EliahForm.OnPlaceToggle(nil);   { disarm }
    if EliahForm.PlaceMode then begin writeln('SMOKE FAIL: toggle did not disarm'); Halt(1); end;

    { component tab bar: two tabs, buttons present, clicking one selects that
      palette row and arms Place (through the real gtk click path) }
    if EliahForm.CompBar.TabCount <> 2 then begin writeln('SMOKE FAIL: tab bar tab count'); Halt(1); end;
    if Length(EliahForm.BarButtons) < 2 then begin writeln('SMOKE FAIL: tab bar empty'); Halt(1); end;
    gtk_button_clicked(EliahForm.BarButtons[1].Handle);
    if EliahForm.Palette.ItemIndex <> EliahForm.BarRows[1] then
      begin writeln('SMOKE FAIL: bar click did not select row'); Halt(1); end;
    if not EliahForm.PlaceMode then begin writeln('SMOKE FAIL: bar click did not arm place'); Halt(1); end;
    EliahForm.OnPlaceToggle(nil);   { disarm again for the checks below }
    EliahForm.Palette.ItemIndex := 1;

    { undo: the place above is on the undo stack -> undo restores the prior count }
    centerW := EliahForm.Dsn.Doc.Count;
    EliahForm.OnUndo(nil);
    if EliahForm.Dsn.Doc.Count <> centerW - 1 then begin writeln('SMOKE FAIL: undo did not revert place'); Halt(1); end;
    { redo by re-placing to keep the rest of the flow stable }
    EliahForm.Palette.ItemIndex := 1;
    EliahForm.OnPlaceToggle(nil);
    EliahForm.OnDesignMouseDown(nil, 1, 150, 150);
    EliahForm.OnPlaceToggle(nil);   { disarm (Place is sticky now) }

    { delete: remove the just-placed node (selected); count drops, sel clears }
    centerW := EliahForm.Dsn.Doc.Count;
    EliahForm.OnDelete(nil);
    if EliahForm.Dsn.Doc.Count <> centerW - 1 then begin writeln('SMOKE FAIL: delete did not remove node'); Halt(1); end;
    if EliahForm.Dsn.Sel >= 0 then begin writeln('SMOKE FAIL: delete did not clear selection'); Halt(1); end;
    { root guard: selecting the form (0) and deleting is a no-op }
    centerW := EliahForm.Dsn.Doc.Count;
    EliahForm.Dsn.Sel := 0;
    EliahForm.OnDelete(nil);
    if EliahForm.Dsn.Doc.Count <> centerW then begin writeln('SMOKE FAIL: root form should not delete'); Halt(1); end;

    { non-visual: place a Timer -> a tray node (non-visual, bottom strip, fixed).
      Left in the doc so the save round-trip below also covers tray serialization. }
    ci := 0;
    while (ci < Length(EliahForm.PaletteNames)) and (EliahForm.PaletteNames[ci] <> 'TTimer') do Inc(ci);
    if ci >= Length(EliahForm.PaletteNames) then
      begin writeln('SMOKE FAIL: TTimer not in registry palette'); Halt(1); end;
    EliahForm.Palette.ItemIndex := ci;
    EliahForm.OnPlaceToggle(nil);
    centerW := EliahForm.Dsn.Doc.Count;
    EliahForm.OnDesignMouseDown(nil, 1, 150, 150);
    if EliahForm.Dsn.Doc.Count <> centerW + 1 then
      begin writeln('SMOKE FAIL: timer place did not add a node'); Halt(1); end;
    if not EliahForm.Dsn.Doc.IsNonVisual(EliahForm.Dsn.Doc.NodeKind(EliahForm.Dsn.Sel)) then
      begin writeln('SMOKE FAIL: placed timer not non-visual'); Halt(1); end;
    EliahForm.Dsn.LayoutTray;
    if EliahForm.Dsn.Doc.NodeY(EliahForm.Dsn.Sel) <
       EliahForm.Dsn.Doc.NodeY(0) + EliahForm.Dsn.Doc.NodeH(0) - 80 then
      begin writeln('SMOKE FAIL: timer not laid out in bottom tray'); Halt(1); end;
    EliahForm.Dsn.BeginDrag(EliahForm.Dsn.Doc.NodeX(EliahForm.Dsn.Sel) + 4, EliahForm.Dsn.Doc.NodeY(EliahForm.Dsn.Sel) + 4);
    if EliahForm.Dsn.Dragging then
      begin writeln('SMOKE FAIL: tray icon should not be draggable'); Halt(1); end;
    EliahForm.Dsn.EndDrag;
    EliahForm.OnPlaceToggle(nil);   { disarm sticky place }

    { inspector on a non-visual node: Caption editable, geometry rows guarded.
      The sample's TTimer is node 5. }
    EliahForm.Dsn.Sel := 5;
    EliahForm.ShowInspector(5);
    EliahForm.FEditRow := 1; EliahForm.ValueEdit.Text := 'Heartbeat'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodeCaption(5) <> 'Heartbeat' then
      begin writeln('SMOKE FAIL: non-visual caption edit ignored'); Halt(1); end;
    { a geometry-row edit must be a no-op on a non-visual node }
    EliahForm.FEditRow := 4; EliahForm.ValueEdit.Text := '999'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodeCaption(5) <> 'Heartbeat' then
      begin writeln('SMOKE FAIL: non-visual geometry edit corrupted node'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeW(5) = 999 then
      begin writeln('SMOKE FAIL: non-visual geometry edit not guarded'); Halt(1); end;
    { extra published prop (Interval) is shown + editable via the bag rows }
    EliahForm.ShowInspector(5);
    if EliahForm.FBagBase <= 0 then
      begin writeln('SMOKE FAIL: timer Interval prop not surfaced'); Halt(1); end;
    { RTTI-driven: the unset Enabled prop shows too, not only the .lfm Interval }
    if Length(EliahForm.FBagNames) < 2 then
      begin writeln('SMOKE FAIL: RTTI prop list missing unset props'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodePropByName(5, 'Interval') <> '1000' then
      begin writeln('SMOKE FAIL: timer Interval prop not loaded'); Halt(1); end;
    EliahForm.FEditRow := EliahForm.FBagBase; EliahForm.ValueEdit.Text := '2000'; EliahForm.ApplyEdit;
    if EliahForm.Dsn.Doc.NodePropByName(5, 'Interval') <> '2000' then
      begin writeln('SMOKE FAIL: Interval bag edit not applied'); Halt(1); end;

    { selection link (M5): designer <-> editor through the shared model }
    EliahForm.SelectNode(EliahForm.Dsn.Doc.FindByName('BtnOk'));
    if EliahForm.Sel.SelectedName <> 'BtnOk' then
      begin writeln('SMOKE FAIL: shared selection model name mismatch'); Halt(1); end;
    EliahForm.EditorToSelection;                 { designer -> editor: load the .lfm + scroll }
    if EliahForm.curFile <> EliahForm.designPath then
      begin writeln('SMOKE FAIL: editor did not load the design file'); Halt(1); end;
    centerW := LfmFindObjectLine(EliahForm.Editor.Text, 'BtnOk');
    if centerW < 0 then
      begin writeln('SMOKE FAIL: BtnOk object line not in editor'); Halt(1); end;
    EliahForm.Sel.Clear; EliahForm.Dsn.Sel := -1;
    EliahForm.SelectFromEditorLine(centerW);     { editor -> designer: line maps to selection }
    if EliahForm.Dsn.Sel <> EliahForm.Dsn.Doc.FindByName('BtnOk') then
      begin writeln('SMOKE FAIL: editor->designer selection failed'); Halt(1); end;

    { command surface: wire OnClick on the selection -> assign handler + gen stub }
    EliahForm.OnWireOnClick(nil);
    if EliahForm.Dsn.Doc.NodePropByName(EliahForm.Dsn.Sel, 'OnClick') <> 'BtnOkClick' then
      begin writeln('SMOKE FAIL: OnClick not assigned'); Halt(1); end;
    if not CodeHasHandler(EliahForm.Editor.Text, 'BtnOkClick') then
      begin writeln('SMOKE FAIL: handler stub not generated'); Halt(1); end;
    { idempotent: wiring again keeps the same editor text (no duplicate stub) }
    centerH := Length(EliahForm.Editor.Text);
    EliahForm.OnWireOnClick(nil);
    if Length(EliahForm.Editor.Text) <> centerH then
      begin writeln('SMOKE FAIL: re-wire duplicated the stub'); Halt(1); end;

    { save round-trip: serialize the docmodel to a temp file (not the repo
      sample), reload it, node count must survive. Same path OnSave uses. }
    centerW := EliahForm.Dsn.Doc.Count;
    if not WriteAllText('/tmp/eliah_rt.lfm', SaveLfmText(EliahForm.Dsn.Doc)) then
      begin writeln('SMOKE FAIL: save write failed'); Halt(1); end;
    sbuf := TIdeBuffer.Create;
    if not sbuf.LoadFromFile('/tmp/eliah_rt.lfm') then
      begin writeln('SMOKE FAIL: save reload failed'); Halt(1); end;
    rtdoc := TDocModel.Create;
    sok := LoadLfmText(sbuf.Text, rtdoc);
    if rtdoc.Count <> centerW then
      begin writeln('SMOKE FAIL: round-trip lost nodes'); Halt(1); end;

    { click empty surface -> selection cleared }
    EliahForm.OnDesignMouseDown(nil, 1, 5, 5);
    if EliahForm.Dsn.Sel >= 0 then begin writeln('SMOKE FAIL: selection not cleared'); Halt(1); end;

    { new design -> a single root form, save target retargeted to untitled }
    EliahForm.OnNew(nil);
    if EliahForm.Dsn.Doc.Count <> 1 then begin writeln('SMOKE FAIL: new design not blank'); Halt(1); end;
    if EliahForm.Dsn.Doc.NodeParent(0) <> -1 then begin writeln('SMOKE FAIL: new root not a form'); Halt(1); end;
    if EliahForm.designPath <> 'untitled.lfm' then begin writeln('SMOKE FAIL: new did not retarget save'); Halt(1); end;

    { status title reflects the open design + node count }
    EliahForm.UpdateTitle;
    if Length(EliahForm.Win.Caption) = 0 then begin writeln('SMOKE FAIL: title empty'); Halt(1); end;

    writeln('SMOKE OK');
  end
  else if arg = '--gui-smoke' then
  begin
    { real-window smoke: run the actual event loop (window maps + paints on a
      live surface), self-quit after 400ms. The suite runs this under xvfb. }
    Application.MainForm := EliahForm;
    g_timeout_add(400, @GuiAutoQuit, nil);
    Application.Run;
    writeln('GUI SMOKE OK');
  end
  else
  begin
    Application.MainForm := EliahForm;
    Application.Run;
  end;
end.
