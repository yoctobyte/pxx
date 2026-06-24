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
     registry;

const
  W_WIN     = 1100;
  H_WIN     = 700;
  W_TREE    = 240;
  W_RIGHT   = 300;
  H_BOTTOM  = 200;
  ERR_H     = 150;        { error-list height at the bottom of the left column }
  TOOLBAR_H = 34;
  PXX_PATH  = 'stable_linux_amd64/default/pinned';
  BUILD_OUT = '/tmp/eliah_build';
  SAMPLE_LFM = 'apps/ide/eliah/sample.lfm';

type
  THandler = class
    Tree: TListBox;
    Editor, Output: TMemo;
    Errors: TListBox;
    Diags: TDiagList;
    Proj: TProject;        { active project; empty MainUnit => single-file compile }
    Props: TListBox;
    ValueEdit: TEdit;
    FEditRow: Integer;     { which inspector row the value edit targets, -1 none }
    Palette: TComboBox;
    PaletteNames: array of AnsiString; { class name backing each palette row }
    PlaceBtn: TButton;
    PlaceMode: Boolean;    { next designer click drops a new widget }
    Dsn: TDesigner;
    DesignBox: TPaintBox;
    RootPaned: TPaned;     { fills the content area; the whole pane layout is its subtree }
    colLeft, midRight, colCenter, colRight, colInspector: TPaned;
    Persp: TPerspective;   { current layout: column visibility + priority compacting }
    panedSeeded: Boolean;  { initial handle positions applied on first allocation }
    startPersp: AnsiString; { perspective applied once after the first allocation }
    Win: TForm;
    dir, curFile, designPath, pendingSnap: AnsiString;
    undoStack: array of AnsiString;
    undoCount: Integer;
    lastW: Integer;        { last width seen by OnFormResize (loop guard) }
    paths: array of AnsiString;
    isdirs: array of Boolean;
    nItems: Integer;
    procedure LoadDir(const d: AnsiString);
    procedure OnTreeClick(Sender: TObject);
    procedure OnCompile(Sender: TObject);
    procedure OnRun(Sender: TObject);
    procedure OnUp(Sender: TObject);
    procedure OnOpenFolder(Sender: TObject);
    procedure OnExit(Sender: TObject);
    procedure OnSave(Sender: TObject);
    procedure OnDelete(Sender: TObject);
    procedure OnNew(Sender: TObject);
    procedure OnErrorClick(Sender: TObject);
    procedure PushUndo(const snap: AnsiString);
    procedure OnUndo(Sender: TObject);
    procedure OpenDesign(const path: AnsiString);
    procedure Relayout(w, h: Integer);
    procedure OnFormResize(Sender: TControl; w, h: Integer);
    procedure OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseMove(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure ShowInspector(idx: Integer);
    procedure UpdateTitle;
    procedure OnPropClick(Sender: TObject);
    procedure OnValueKey(Sender: TControl; KeyCode: Integer);
    procedure ApplyEdit;
    procedure OnPlaceToggle(Sender: TObject);
    procedure OnToggleLeft(Sender: TObject);
    procedure OnToggleOutput(Sender: TObject);
    procedure OnToggleRight(Sender: TObject);
    procedure SetPerspective(const name: AnsiString);
    procedure ApplyLayout(w: Integer);
    procedure OnPerspCode(Sender: TObject);
    procedure OnPerspDesign(Sender: TObject);
    procedure OnPerspSplit(Sender: TObject);
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

{ case-insensitive '.lfm' suffix test }
function EndsWithLfm(const s: AnsiString): Boolean;
var n: Integer; tail: AnsiString;
begin
  n := Length(s);
  if n < 4 then begin EndsWithLfm := False; Exit; end;
  tail := LowerCase(Copy(s, n - 3, 4));
  EndsWithLfm := tail = '.lfm';
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

procedure THandler.LoadDir(const d: AnsiString);
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

procedure THandler.OnTreeClick(Sender: TObject);
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
  if b.LoadFromFile(curFile) then Editor.Text := b.Text
  else Editor.Text := '(could not open ' + curFile + ')';
  { a .lfm also loads into the designer surface }
  if EndsWithLfm(curFile) then OpenDesign(curFile);
end;

{ click a diagnostic -> jump the editor to its line (compiler lines are 1-based,
  the memo caret is 0-based) }
procedure THandler.OnErrorClick(Sender: TObject);
var idx, line: Integer;
begin
  idx := Errors.ItemIndex;
  if (idx < 0) or (idx >= Diags.Count) then Exit;
  line := Diags.DiagLine(idx);
  if line > 0 then Editor.CaretToLine(line - 1);
end;

{ start a blank design: a single root form. Save will prompt to a fresh path
  (untitled.lfm) so it never clobbers the previously-open file. }
procedure THandler.OnNew(Sender: TObject);
var d: TDocModel;
begin
  d := TDocModel.Create;
  d.AddNode(wkForm, 'Form1', -1, 12, 12, 320, 240);
  Dsn.Doc := d;
  Dsn.Sel := -1;
  Dsn.EndDrag;
  designPath := 'untitled.lfm';
  if DesignBox <> nil then DesignBox.Invalidate;
  ShowInspector(-1);
  Output.Text := '$ new design (untitled.lfm)';
end;

{ delete the selected node (and its children); the root form is kept }
procedure THandler.OnDelete(Sender: TObject);
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
procedure THandler.OpenDesign(const path: AnsiString);
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

procedure THandler.OnCompile(Sender: TObject);
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

procedure THandler.OnRun(Sender: TObject);
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

procedure THandler.OnUp(Sender: TObject);
begin
  LoadDir(ParentDir(dir));
end;

{ File -> Open Folder: pick a directory and make it the project tree root }
procedure THandler.OnOpenFolder(Sender: TObject);
var p: AnsiString;
begin
  p := SelectFolderDialog('Open Project Folder');
  if p <> '' then LoadDir(p);
end;

procedure THandler.OnExit(Sender: TObject);
begin
  Halt(0);
end;

{ reflow for a content area of w x h. The pane layout is the RootPaned subtree —
  GtkPaned owns the internal splits, so we only resize the root to fill the area
  below the toolbar. Toolbar widgets stay pinned at the top. }
procedure THandler.Relayout(w, h: Integer);
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
procedure THandler.ApplyLayout(w: Integer);
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
procedure THandler.SetPerspective(const name: AnsiString);
begin
  if Persp = nil then Exit;
  Persp.SetVisible(Persp.IndexOf('left'),   True);
  Persp.SetVisible(Persp.IndexOf('center'), name <> 'design');
  Persp.SetVisible(Persp.IndexOf('right'),  name <> 'code');
  if lastW > 0 then ApplyLayout(lastW);
end;

procedure THandler.OnPerspCode(Sender: TObject);   begin SetPerspective('code');   end;
procedure THandler.OnPerspDesign(Sender: TObject); begin SetPerspective('design'); end;
procedure THandler.OnPerspSplit(Sender: TObject);  begin SetPerspective('split');  end;

{ View-menu toggles flip a column's visibility choice, then re-apply. }
procedure THandler.OnToggleLeft(Sender: TObject);
var i: Integer;
begin
  if Persp = nil then Exit;
  i := Persp.IndexOf('left');
  Persp.SetVisible(i, not Persp.PaneVisible(i));
  if lastW > 0 then ApplyLayout(lastW);
end;

procedure THandler.OnToggleRight(Sender: TObject);
var i: Integer;
begin
  if Persp = nil then Exit;
  i := Persp.IndexOf('right');
  Persp.SetVisible(i, not Persp.PaneVisible(i));
  if lastW > 0 then ApplyLayout(lastW);
end;

procedure THandler.OnToggleOutput(Sender: TObject);
begin
  if colCenter <> nil then colCenter.Toggle(2, 0);    { vertical sub-pane: build/run output }
end;

procedure THandler.OnFormResize(Sender: TControl; w, h: Integer);
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
procedure THandler.OnSave(Sender: TObject);
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
procedure THandler.UpdateTitle;
var s: AnsiString;
begin
  if (Win = nil) or (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  s := 'Eliah - ' + designPath + ' (' + IntToStr(Dsn.Doc.Count) + ' nodes)';
  if (Dsn.Sel >= 0) and (Dsn.Sel < Dsn.Doc.Count) then
    s := s + '  [sel: ' + Dsn.Doc.KindName(Dsn.Doc.NodeKind(Dsn.Sel)) +
         ' ' + Dsn.Doc.NodeCaption(Dsn.Sel) + ']';
  Win.Caption := s;
end;

procedure THandler.ShowInspector(idx: Integer);
var d: TDocModel;
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
  Props.AddItem('Left:    ' + IntToStr(d.NodeX(idx)));
  Props.AddItem('Top:     ' + IntToStr(d.NodeY(idx)));
  Props.AddItem('Width:   ' + IntToStr(d.NodeW(idx)));
  Props.AddItem('Height:  ' + IntToStr(d.NodeH(idx)));
end;

{ undo stack holds .lfm snapshots (SaveLfmText round-trips losslessly) }
procedure THandler.PushUndo(const snap: AnsiString);
begin
  SetLength(undoStack, undoCount + 1);
  undoStack[undoCount] := snap;
  Inc(undoCount);
end;

procedure THandler.OnUndo(Sender: TObject);
var d: TDocModel; ok: Boolean;
begin
  if undoCount <= 0 then begin Output.Text := '$ nothing to undo'; Exit; end;
  Dec(undoCount);
  d := TDocModel.Create;
  ok := LoadLfmText(undoStack[undoCount], d);
  Dsn.Doc := d;
  Dsn.Sel := -1;
  Dsn.EndDrag;
  if DesignBox <> nil then DesignBox.Invalidate;
  ShowInspector(-1);
  Output.Text := '$ undo (' + IntToStr(undoCount) + ' left)';
end;

procedure THandler.OnPlaceToggle(Sender: TObject);
begin
  PlaceMode := not PlaceMode;
  if PlaceMode then PlaceBtn.Caption := 'Place*' else PlaceBtn.Caption := 'Place';
end;

procedure THandler.OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
var idx: Integer; k: TWidgetKind;
begin
  { snapshot the pre-action state; committed to undo only if the doc changes }
  pendingSnap := SaveLfmText(Dsn.Doc);
  if PlaceMode then
  begin
    { drop a new widget of the palette kind, parented to the form (node 0) }
    PushUndo(pendingSnap);
    k := wkButton;
    if (Palette.ItemIndex >= 0) and (Palette.ItemIndex < Length(PaletteNames)) then
      CompPlaceKind(PaletteNames[Palette.ItemIndex], k);
    idx := Dsn.Doc.AddNode(k, Dsn.Doc.KindName(k), 0, X, Y, 80, 24);
    Dsn.Sel := idx;
    OnPlaceToggle(nil);          { one-shot: leave place mode after dropping }
    DesignBox.Invalidate;
    ShowInspector(idx);
    Exit;
  end;
  idx := Dsn.BeginDrag(X, Y);
  DesignBox.Invalidate;
  ShowInspector(idx);
end;

procedure THandler.OnDesignMouseMove(Sender: TControl; Button, X, Y: Integer);
begin
  if not (Dsn.Dragging or Dsn.Resizing) then Exit;
  Dsn.DragTo(X, Y);
  DesignBox.Invalidate;
  ShowInspector(Dsn.Sel);
end;

procedure THandler.OnDesignMouseUp(Sender: TControl; Button, X, Y: Integer);
begin
  Dsn.EndDrag;
  { commit the pre-drag snapshot only if a move/resize actually changed the doc }
  if (pendingSnap <> '') and (SaveLfmText(Dsn.Doc) <> pendingSnap) then
    PushUndo(pendingSnap);
  pendingSnap := '';
  ShowInspector(Dsn.Sel);
end;

{ click an inspector row -> load that field's current value into the edit }
procedure THandler.OnPropClick(Sender: TObject);
var d: TDocModel;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) then Exit;
  d := Dsn.Doc;
  FEditRow := Props.ItemIndex;
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
procedure THandler.OnValueKey(Sender: TControl; KeyCode: Integer);
begin
  if (KeyCode = 65293) or (KeyCode = 65421) then ApplyEdit;
end;

procedure THandler.ApplyEdit;
var d: TDocModel; v: AnsiString;
begin
  if (Dsn = nil) or (Dsn.Doc = nil) or (Dsn.Sel < 0) then Exit;
  d := Dsn.Doc;
  v := ValueEdit.Text;
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
  Form1: TForm;
  H: THandler;
  Props: TListBox;
  ValueEdit: TEdit;
  Palette: TComboBox;
  PlaceBtn: TButton;
  DesignBox: TPaintBox;
  Dsn: TDesigner;
  btn: TButton;
  arg, startDir, parg: AnsiString;
  pix: Integer;
  centerW, centerH, contentH: Integer;
  colLeft, midRight, colCenter, colRight, colInspector: TPaned;
  sbuf: TIdeBuffer;
  sok: Boolean;
  rtdoc: TDocModel;
  MainMenu: TMainMenu;
  FileMenu, EditMenu, BuildMenu, ViewMenu, mi: TMenuItem;
  comps: TRegEntryArr;
  ci: Integer;
  pk: TWidgetKind;

function MkMenuItem(const cap: AnsiString; parent: TMenuItem): TMenuItem;
var it: TMenuItem;
begin
  it := TMenuItem.Create(nil);
  it.Caption := cap;
  parent.Add(it);
  MkMenuItem := it;
end;

function MkButton(const cap: AnsiString; x: Integer): TButton;
var b: TButton;
begin
  b := TButton.Create(nil);
  b.Parent := Form1;
  b.Caption := cap;
  b.SetBounds(x, 3, 80, 26);
  MkButton := b;
end;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Eliah - IDE';
  Form1.SetBounds(0, 0, W_WIN, H_WIN);

  contentH := H_WIN - TOOLBAR_H;
  centerW := W_WIN - W_TREE - W_RIGHT;
  centerH := contentH - H_BOTTOM;

  H := THandler.Create;
  H.Proj := TProject.Create;

  { ── Pane layout is one TPaned tree filling the content area below the toolbar.
    GtkPaned owns all splitter sizing + drag; we only seed initial handle
    positions and resize the root on form-resize. No per-pane absolute math.

        Root (H) ──┬─ colLeft (V): Tree / Errors
                   └─ midRight (H) ─┬─ colCenter (V): Editor / Output
                                    └─ colRight  (V): DesignBox / colInspector(V): Props / ValueEdit

    Each leaf's first child fills pane 1, the second fills pane 2 (set Parent in
    that order). ── }
  H.RootPaned := TPaned.Create(nil);                 { horizontal: left | rest }
  H.RootPaned.Parent := Form1;
  H.RootPaned.SetBounds(0, TOOLBAR_H, W_WIN, contentH);

  colLeft := TPaned.Create(nil); colLeft.Vertical := True;
  colLeft.Parent := H.RootPaned;

  midRight := TPaned.Create(nil);                    { horizontal: center | right }
  midRight.Parent := H.RootPaned;

  colCenter := TPaned.Create(nil); colCenter.Vertical := True;
  colCenter.Parent := midRight;

  colRight := TPaned.Create(nil); colRight.Vertical := True;
  colRight.Parent := midRight;

  colInspector := TPaned.Create(nil); colInspector.Vertical := True;

  { keep references so OnFormResize can seed/track handle positions }
  H.colLeft := colLeft; H.midRight := midRight; H.colCenter := colCenter;
  H.colRight := colRight; H.colInspector := colInspector;
  H.panedSeeded := False;

  { the three horizontal columns + their compacting priorities (higher survives a
    shrink longer). center (editor) is most important, right (designer) least. }
  H.Persp := TPerspective.Create;
  H.Persp.SetName('Split');
  H.Persp.AddPane('left',   W_TREE,  50, True);
  H.Persp.AddPane('center', 320,     90, True);
  H.Persp.AddPane('right',  W_RIGHT, 40, True);

  H.Tree := TListBox.Create(nil);
  H.Tree.Parent := colLeft;                          { pane 1 of colLeft }
  H.Tree.OnClick := @H.OnTreeClick;

  { error list under the tree: compile diagnostics, click -> jump editor }
  H.Diags := TDiagList.Create;
  H.Errors := TListBox.Create(nil);
  H.Errors.Parent := colLeft;                        { pane 2 of colLeft }
  H.Errors.OnClick := @H.OnErrorClick;

  H.Editor := TMemo.Create(nil);
  H.Editor.Parent := colCenter;                      { pane 1 of colCenter }

  H.Output := TMemo.Create(nil);
  H.Output.Parent := colCenter;                      { pane 2 of colCenter }
  H.Output.Text := 'build output appears here';

  { designer: box-emulated preview painted from the garin docmodel (no live
    widgets). Seed the surface by loading a sample .lfm through the garin loader
    (box-emulation parser, not the live-component streamer). }
  Dsn := TDesigner.Create;
  Dsn.Doc := TDocModel.Create;
  sbuf := TIdeBuffer.Create;
  if sbuf.LoadFromFile(SAMPLE_LFM) then
    sok := LoadLfmText(sbuf.Text, Dsn.Doc);

  DesignBox := TPaintBox.Create(nil);
  DesignBox.Parent := colRight;                      { pane 1 of colRight }
  DesignBox.OnPaint := @Dsn.Paint;
  { mouse-select + drag-move: down hit-tests & grabs, move drags the selected
    box, up releases. }
  DesignBox.OnMouseDown := @H.OnDesignMouseDown;
  DesignBox.OnMouseMove := @H.OnDesignMouseMove;
  DesignBox.OnMouseUp   := @H.OnDesignMouseUp;

  colInspector.Parent := colRight;                   { pane 2 of colRight }

  Props := TListBox.Create(nil);
  Props.Parent := colInspector;                      { pane 1 of colInspector }
  Props.AddItem('object inspector (M1)');
  Props.OnClick := @H.OnPropClick;

  { value editor: pick a prop row above, type here, Enter commits to docmodel }
  ValueEdit := TEdit.Create(nil);
  ValueEdit.Parent := colInspector;                  { pane 2 of colInspector }
  ValueEdit.OnKeyDown := @H.OnValueKey;

  H.Dsn := Dsn;
  H.DesignBox := DesignBox;
  H.Props := Props;
  H.ValueEdit := ValueEdit;
  H.FEditRow := -1;
  H.designPath := SAMPLE_LFM;   { seeded from the sample; Save targets it until a .lfm is opened }
  H.Win := Form1;
  H.lastW := -1;

  { main menu bar }
  MainMenu := TMainMenu.Create(nil);
  Form1.Menu := MainMenu;

  FileMenu := TMenuItem.Create(nil); FileMenu.Caption := '&File'; MainMenu.Items.Add(FileMenu);
  mi := MkMenuItem('&New',          FileMenu); mi.OnClick := @H.OnNew;
  mi := MkMenuItem('&Open Folder...', FileMenu); mi.OnClick := @H.OnOpenFolder;
  mi := MkMenuItem('&Save',         FileMenu); mi.OnClick := @H.OnSave;
  mi := MkMenuItem('E&xit',         FileMenu); mi.OnClick := @H.OnExit;

  EditMenu := TMenuItem.Create(nil); EditMenu.Caption := '&Edit'; MainMenu.Items.Add(EditMenu);
  mi := MkMenuItem('&Undo',   EditMenu); mi.OnClick := @H.OnUndo;
  mi := MkMenuItem('&Delete', EditMenu); mi.OnClick := @H.OnDelete;

  BuildMenu := TMenuItem.Create(nil); BuildMenu.Caption := '&Build'; MainMenu.Items.Add(BuildMenu);
  mi := MkMenuItem('&Compile', BuildMenu); mi.OnClick := @H.OnCompile;
  mi := MkMenuItem('&Run',     BuildMenu); mi.OnClick := @H.OnRun;

  ViewMenu := TMenuItem.Create(nil); ViewMenu.Caption := '&View'; MainMenu.Items.Add(ViewMenu);
  mi := MkMenuItem('&Code Layout',   ViewMenu); mi.OnClick := @H.OnPerspCode;
  mi := MkMenuItem('&Design Layout', ViewMenu); mi.OnClick := @H.OnPerspDesign;
  mi := MkMenuItem('&Split Layout',  ViewMenu); mi.OnClick := @H.OnPerspSplit;
  mi := MkMenuItem('Toggle &Left Panel',  ViewMenu); mi.OnClick := @H.OnToggleLeft;
  mi := MkMenuItem('Toggle &Output',      ViewMenu); mi.OnClick := @H.OnToggleOutput;
  mi := MkMenuItem('Toggle &Right Panel', ViewMenu); mi.OnClick := @H.OnToggleRight;

  Form1.OnResize := @H.OnFormResize;   { reflow panes on window resize }

  btn := MkButton('Up',      4);   btn.OnClick := @H.OnUp;
  btn := MkButton('Compile', 90);  btn.OnClick := @H.OnCompile;
  btn := MkButton('Run',     176); btn.OnClick := @H.OnRun;
  btn := MkButton('Save',    466); btn.OnClick := @H.OnSave;
  btn := MkButton('Del',     552); btn.OnClick := @H.OnDelete;
  btn := MkButton('New',     638); btn.OnClick := @H.OnNew;
  btn := MkButton('Undo',    724); btn.OnClick := @H.OnUndo;

  { palette: pick a widget kind, hit Place, then click the designer to drop it.
    Registry-driven: every registered visual component (descends from TControl)
    the designer can place appears here automatically — RegisterClass'ing a new
    placeable widget surfaces it with no edit to this list. }
  Palette := TComboBox.Create(nil);
  Palette.Parent := Form1;
  Palette.SetBounds(266, 3, 110, 26);
  comps := EnumDescendants('TComponent', False);
  SetLength(H.PaletteNames, 0);
  for ci := 0 to Length(comps) - 1 do
  begin
    { both visual widgets and non-visual components belong here — CompPlaceKind
      is the gate (it knows which class names the docmodel can place; non-visual
      ones land in the tray, visual ones on the canvas). }
    if not CompPlaceKind(comps[ci].Name, pk) then Continue;
    Palette.AddItem(CompDisplay(comps[ci].Name));
    SetLength(H.PaletteNames, Length(H.PaletteNames) + 1);
    H.PaletteNames[Length(H.PaletteNames) - 1] := comps[ci].Name;
  end;
  Palette.ItemIndex := 0;

  PlaceBtn := TButton.Create(nil);
  PlaceBtn.Parent := Form1;
  PlaceBtn.Caption := 'Place';
  PlaceBtn.SetBounds(382, 3, 80, 26);
  PlaceBtn.OnClick := @H.OnPlaceToggle;

  H.Palette := Palette;
  H.PlaceBtn := PlaceBtn;
  H.PlaceMode := False;

  arg := '';
  startDir := '.';
  H.startPersp := '';
  for pix := 1 to ParamCount do
  begin
    parg := ParamStr(pix);
    if parg = '--smoke' then arg := '--smoke'
    else if parg = '--code' then H.startPersp := 'code'
    else if parg = '--design' then H.startPersp := 'design'
    else if parg = '--split' then H.startPersp := 'split'
    else if (Length(parg) >= 2) and (parg[1] = '-') and (parg[2] = '-') then
      { ignore unknown -- flag }
    else
      startDir := parg;                 { a bare argument is the start directory }
  end;
  H.LoadDir(startDir);

  Form1.Realize;

  if arg = '--smoke' then
  begin
    if H.nItems < 1 then begin writeln('SMOKE FAIL: empty tree'); Halt(1); end;

    { sample .lfm loaded into the designer docmodel }
    if H.Dsn.Doc.Count <> 6 then begin writeln('SMOKE FAIL: sample.lfm not loaded'); Halt(1); end;
    if H.Dsn.Doc.NodeCaption(3) <> 'OK' then begin writeln('SMOKE FAIL: lfm OK button missing'); Halt(1); end;
    if H.Dsn.Doc.NodeX(3) <> 28 then begin writeln('SMOKE FAIL: lfm abs coord wrong'); Halt(1); end;
    { the sample's TTimer streams in as a non-visual tray node }
    if not H.Dsn.Doc.IsNonVisual(H.Dsn.Doc.NodeKind(5)) then
      begin writeln('SMOKE FAIL: sample TTimer not a non-visual node'); Halt(1); end;

    { pane layout is the RootPaned subtree; reflow resizes the root to fill the
      content area below the toolbar (GtkPaned owns the internal splits). }
    if H.RootPaned = nil then begin writeln('SMOKE FAIL: no root paned'); Halt(1); end;
    H.Relayout(1400, 900);
    if H.RootPaned.Width <> 1400 then begin writeln('SMOKE FAIL: root paned width did not reflow'); Halt(1); end;
    if H.RootPaned.Height <> (900 - TOOLBAR_H) then begin writeln('SMOKE FAIL: root paned height did not reflow'); Halt(1); end;
    { tiny window clamps the content height instead of going negative }
    H.Relayout(200, 120);
    if H.RootPaned.Height < 160 then begin writeln('SMOKE FAIL: reflow did not clamp height'); Halt(1); end;
    H.Relayout(W_WIN, H_WIN);   { restore }

    { headless has no real allocation, so drive layout with an explicit width.
      View-menu toggle flips the left column's visibility choice. }
    H.OnToggleLeft(nil); H.ApplyLayout(W_WIN);
    if H.RootPaned.CollapsedPane <> 1 then begin writeln('SMOKE FAIL: left panel did not collapse'); Halt(1); end;
    H.OnToggleLeft(nil); H.ApplyLayout(W_WIN);
    if H.RootPaned.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: left panel did not restore'); Halt(1); end;

    { perspectives are visibility configs of midRight = [center | right] }
    H.SetPerspective('code'); H.ApplyLayout(W_WIN);
    if H.midRight.CollapsedPane <> 2 then begin writeln('SMOKE FAIL: code persp did not hide right'); Halt(1); end;
    H.SetPerspective('design'); H.ApplyLayout(W_WIN);
    if H.midRight.CollapsedPane <> 1 then begin writeln('SMOKE FAIL: design persp did not hide center'); Halt(1); end;
    H.SetPerspective('split'); H.ApplyLayout(W_WIN);
    if H.midRight.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: split persp did not show both'); Halt(1); end;

    { priority compacting: a width below sum(mins) auto-collapses the lowest
      priority column (right=designer), even in the split perspective. }
    H.SetPerspective('split'); H.ApplyLayout(400);
    if H.midRight.CollapsedPane <> 2 then begin writeln('SMOKE FAIL: compacting did not drop right'); Halt(1); end;
    H.ApplyLayout(W_WIN);
    if H.midRight.CollapsedPane <> 0 then begin writeln('SMOKE FAIL: widening did not restore right'); Halt(1); end;

    { open any .lfm from the tree: clicking a .lfm reloads the designer + retargets Save }
    H.Dsn.Doc := TDocModel.Create;   { wipe to prove OpenDesign reloads }
    H.designPath := '';
    H.OpenDesign('apps/ide/eliah/sample.lfm');
    if H.Dsn.Doc.Count <> 6 then begin writeln('SMOKE FAIL: OpenDesign did not load'); Halt(1); end;
    if H.designPath <> 'apps/ide/eliah/sample.lfm' then begin writeln('SMOKE FAIL: designPath not set'); Halt(1); end;
    if not EndsWithLfm('Foo.LFM') then begin writeln('SMOKE FAIL: EndsWithLfm case'); Halt(1); end;
    if EndsWithLfm('foo.pas') then begin writeln('SMOKE FAIL: EndsWithLfm false-pos'); Halt(1); end;

    H.LoadDir('apps/ide/garin');
    H.Tree.ItemIndex := H.nItems - 1;
    H.OnTreeClick(nil);
    if Length(H.Editor.Text) = 0 then begin writeln('SMOKE FAIL: editor empty'); Halt(1); end;
    H.curFile := 'apps/ide/garin/buffer.pas';
    H.OnCompile(nil);
    if Length(H.Output.Text) = 0 then begin writeln('SMOKE FAIL: no compile output'); Halt(1); end;

    { diagnostics: compile a deliberately broken unit -> error list populated,
      click jumps the editor (no crash). }
    if not WriteAllText('/tmp/eliah_bad.pas', 'program bad;' + #10 + 'begin' + #10 + '  x := 1;' + #10 + 'end.' + #10) then
      begin writeln('SMOKE FAIL: could not write bad.pas'); Halt(1); end;
    H.curFile := '/tmp/eliah_bad.pas';
    H.OnCompile(nil);
    if H.Diags.Count < 1 then begin writeln('SMOKE FAIL: no diagnostics parsed'); Halt(1); end;
    if H.Diags.DiagLine(0) <> 3 then begin writeln('SMOKE FAIL: diag line wrong'); Halt(1); end;
    H.Errors.ItemIndex := 0;
    H.OnErrorClick(nil);   { jump to the error line — must not crash }

    { designer mouse-select: click inside the sample OK button (x=28..108,
      y=92..120) -> it must become the selection and fill the inspector. }
    H.OnDesignMouseDown(nil, 1, 40, 100);
    if H.Dsn.Sel < 0 then begin writeln('SMOKE FAIL: no node selected'); Halt(1); end;
    if H.Dsn.Doc.NodeCaption(H.Dsn.Sel) <> 'OK' then
      begin writeln('SMOKE FAIL: wrong node selected'); Halt(1); end;

    { drag-move: grab the OK button at (40,100) — origin (28,92), so the grab
      offset is (12,8) — and move the cursor to (70,140); the node origin must
      follow to (70-12, 140-8) = (58,132). }
    H.OnDesignMouseDown(nil, 1, 40, 100);
    H.OnDesignMouseMove(nil, 1, 70, 140);
    H.OnDesignMouseUp(nil, 1, 70, 140);
    if (H.Dsn.Doc.NodeX(H.Dsn.Sel) <> 58) or (H.Dsn.Doc.NodeY(H.Dsn.Sel) <> 132) then
      begin writeln('SMOKE FAIL: drag-move did not reposition node'); Halt(1); end;
    { move after release must NOT keep dragging }
    H.OnDesignMouseMove(nil, 0, 200, 200);
    if (H.Dsn.Doc.NodeX(H.Dsn.Sel) <> 58) then
      begin writeln('SMOKE FAIL: node moved after mouse-up'); Halt(1); end;

    { resize: OK button now at (58,132,80,28) -> BR corner at (138,160). Grab it
      and drag to (158,180): origin stays, W/H grow by 20 -> (58,132,100,48). }
    H.OnDesignMouseDown(nil, 1, 138, 160);
    if not H.Dsn.Resizing then begin writeln('SMOKE FAIL: handle did not start resize'); Halt(1); end;
    H.OnDesignMouseMove(nil, 1, 158, 180);
    H.OnDesignMouseUp(nil, 1, 158, 180);
    if (H.Dsn.Doc.NodeX(H.Dsn.Sel) <> 58) or (H.Dsn.Doc.NodeY(H.Dsn.Sel) <> 132) or
       (H.Dsn.Doc.NodeW(H.Dsn.Sel) <> 100) or (H.Dsn.Doc.NodeH(H.Dsn.Sel) <> 48) then
      begin writeln('SMOKE FAIL: BR resize wrong bounds'); Halt(1); end;

    { editable inspector: pick a row, type a value, commit -> docmodel updates }
    H.FEditRow := 1; H.ValueEdit.Text := 'Apply'; H.ApplyEdit;
    if H.Dsn.Doc.NodeCaption(H.Dsn.Sel) <> 'Apply' then
      begin writeln('SMOKE FAIL: caption edit not applied'); Halt(1); end;
    H.FEditRow := 4; H.ValueEdit.Text := '120'; H.ApplyEdit;
    if H.Dsn.Doc.NodeW(H.Dsn.Sel) <> 120 then
      begin writeln('SMOKE FAIL: width edit not applied'); Halt(1); end;
    { commit via the Enter key path (Return keyval) }
    H.FEditRow := 3; H.ValueEdit.Text := '200'; H.OnValueKey(nil, 65293);
    if H.Dsn.Doc.NodeY(H.Dsn.Sel) <> 200 then
      begin writeln('SMOKE FAIL: Enter did not commit Top edit'); Halt(1); end;
    { malformed int keeps the old value (StrToIntDef fallback) }
    H.FEditRow := 2; H.ValueEdit.Text := 'xyz'; H.ApplyEdit;
    if H.Dsn.Doc.NodeX(H.Dsn.Sel) <> 58 then
      begin writeln('SMOKE FAIL: bad int should keep old Left'); Halt(1); end;

    { palette place: arm Place, click empty surface -> a new node is dropped,
      parented to the form, selected; Place is one-shot (auto-disarms). }
    H.Palette.ItemIndex := 1;        { Label }
    H.OnPlaceToggle(nil);
    if not H.PlaceMode then begin writeln('SMOKE FAIL: place not armed'); Halt(1); end;
    centerW := H.Dsn.Doc.Count;      { reuse scratch int: node count before }
    H.OnDesignMouseDown(nil, 1, 150, 150);
    if H.Dsn.Doc.Count <> centerW + 1 then
      begin writeln('SMOKE FAIL: place did not add a node'); Halt(1); end;
    if H.Dsn.Sel <> centerW then
      begin writeln('SMOKE FAIL: placed node not selected'); Halt(1); end;
    if H.Dsn.Doc.NodeParent(H.Dsn.Sel) <> 0 then
      begin writeln('SMOKE FAIL: placed node not parented to form'); Halt(1); end;
    pk := wkButton;
    CompPlaceKind(H.PaletteNames[H.Palette.ItemIndex], pk);
    if H.Dsn.Doc.NodeKind(H.Dsn.Sel) <> pk then
      begin writeln('SMOKE FAIL: placed node wrong kind'); Halt(1); end;
    if Length(H.PaletteNames) < 7 then
      begin writeln('SMOKE FAIL: registry palette underpopulated'); Halt(1); end;
    if H.PlaceMode then begin writeln('SMOKE FAIL: place mode not one-shot'); Halt(1); end;

    { undo: the place above is on the undo stack -> undo restores the prior count }
    centerW := H.Dsn.Doc.Count;
    H.OnUndo(nil);
    if H.Dsn.Doc.Count <> centerW - 1 then begin writeln('SMOKE FAIL: undo did not revert place'); Halt(1); end;
    { redo by re-placing to keep the rest of the flow stable }
    H.Palette.ItemIndex := 1;
    H.OnPlaceToggle(nil);
    H.OnDesignMouseDown(nil, 1, 150, 150);

    { delete: remove the just-placed node (selected); count drops, sel clears }
    centerW := H.Dsn.Doc.Count;
    H.OnDelete(nil);
    if H.Dsn.Doc.Count <> centerW - 1 then begin writeln('SMOKE FAIL: delete did not remove node'); Halt(1); end;
    if H.Dsn.Sel >= 0 then begin writeln('SMOKE FAIL: delete did not clear selection'); Halt(1); end;
    { root guard: selecting the form (0) and deleting is a no-op }
    centerW := H.Dsn.Doc.Count;
    H.Dsn.Sel := 0;
    H.OnDelete(nil);
    if H.Dsn.Doc.Count <> centerW then begin writeln('SMOKE FAIL: root form should not delete'); Halt(1); end;

    { non-visual: place a Timer -> a tray node (non-visual, bottom strip, fixed).
      Left in the doc so the save round-trip below also covers tray serialization. }
    ci := 0;
    while (ci < Length(H.PaletteNames)) and (H.PaletteNames[ci] <> 'TTimer') do Inc(ci);
    if ci >= Length(H.PaletteNames) then
      begin writeln('SMOKE FAIL: TTimer not in registry palette'); Halt(1); end;
    H.Palette.ItemIndex := ci;
    H.OnPlaceToggle(nil);
    centerW := H.Dsn.Doc.Count;
    H.OnDesignMouseDown(nil, 1, 150, 150);
    if H.Dsn.Doc.Count <> centerW + 1 then
      begin writeln('SMOKE FAIL: timer place did not add a node'); Halt(1); end;
    if not H.Dsn.Doc.IsNonVisual(H.Dsn.Doc.NodeKind(H.Dsn.Sel)) then
      begin writeln('SMOKE FAIL: placed timer not non-visual'); Halt(1); end;
    H.Dsn.LayoutTray;
    if H.Dsn.Doc.NodeY(H.Dsn.Sel) <
       H.Dsn.Doc.NodeY(0) + H.Dsn.Doc.NodeH(0) - 80 then
      begin writeln('SMOKE FAIL: timer not laid out in bottom tray'); Halt(1); end;
    H.Dsn.BeginDrag(H.Dsn.Doc.NodeX(H.Dsn.Sel) + 4, H.Dsn.Doc.NodeY(H.Dsn.Sel) + 4);
    if H.Dsn.Dragging then
      begin writeln('SMOKE FAIL: tray icon should not be draggable'); Halt(1); end;
    H.Dsn.EndDrag;

    { save round-trip: serialize the docmodel to a temp file (not the repo
      sample), reload it, node count must survive. Same path OnSave uses. }
    centerW := H.Dsn.Doc.Count;
    if not WriteAllText('/tmp/eliah_rt.lfm', SaveLfmText(H.Dsn.Doc)) then
      begin writeln('SMOKE FAIL: save write failed'); Halt(1); end;
    sbuf := TIdeBuffer.Create;
    if not sbuf.LoadFromFile('/tmp/eliah_rt.lfm') then
      begin writeln('SMOKE FAIL: save reload failed'); Halt(1); end;
    rtdoc := TDocModel.Create;
    sok := LoadLfmText(sbuf.Text, rtdoc);
    if rtdoc.Count <> centerW then
      begin writeln('SMOKE FAIL: round-trip lost nodes'); Halt(1); end;

    { click empty surface -> selection cleared }
    H.OnDesignMouseDown(nil, 1, 5, 5);
    if H.Dsn.Sel >= 0 then begin writeln('SMOKE FAIL: selection not cleared'); Halt(1); end;

    { new design -> a single root form, save target retargeted to untitled }
    H.OnNew(nil);
    if H.Dsn.Doc.Count <> 1 then begin writeln('SMOKE FAIL: new design not blank'); Halt(1); end;
    if H.Dsn.Doc.NodeParent(0) <> -1 then begin writeln('SMOKE FAIL: new root not a form'); Halt(1); end;
    if H.designPath <> 'untitled.lfm' then begin writeln('SMOKE FAIL: new did not retarget save'); Halt(1); end;

    { status title reflects the open design + node count }
    H.UpdateTitle;
    if Length(H.Win.Caption) = 0 then begin writeln('SMOKE FAIL: title empty'); Halt(1); end;

    writeln('SMOKE OK');
  end
  else
  begin
    Application.MainForm := Form1;
    Application.Run;
  end;
end.
