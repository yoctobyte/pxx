program eliah;

{ Eliah — GTK face of the IDE.

  A single sizable window, fixed tiled layout (no multi-window / modal). Toolbar
  plus three live panes:

    [ Up  Compile  Run ]
    +--------+----------------------------------+
    | proj   |   editor                         |
    | tree   |                                  |
    |        +----------------------------------+
    |        |   build / run output             |
    +--------+----------------------------------+

  Working: the project tree lists a directory (click a folder to descend, "../"
  to go up, a file to open it in the editor through the garin buffer); Compile
  runs the pinned compiler on the open .pas and shows its output; Run executes
  the built binary. The right column is the designer: a TPaintBox paints the
  garin docmodel as emulated boxes, clicking a box hit-tests the model and shows
  a selection outline + the node's fields in the object-inspector pane below. }

uses gtk3, controls, stdctrls, extctrls, graphics, forms, sysutils,
     buffer, runner, docmodel, designer, lfmload, builder;

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
    Props: TListBox;
    ValueEdit: TEdit;
    FEditRow: Integer;     { which inspector row the value edit targets, -1 none }
    Palette: TComboBox;
    PlaceBtn: TButton;
    PlaceMode: Boolean;    { next designer click drops a new widget }
    Dsn: TDesigner;
    DesignBox: TPaintBox;
    dir, curFile, designPath: AnsiString;
    paths: array of AnsiString;
    isdirs: array of Boolean;
    nItems: Integer;
    procedure LoadDir(const d: AnsiString);
    procedure OnTreeClick(Sender: TObject);
    procedure OnCompile(Sender: TObject);
    procedure OnRun(Sender: TObject);
    procedure OnUp(Sender: TObject);
    procedure OnSave(Sender: TObject);
    procedure OnDelete(Sender: TObject);
    procedure OnErrorClick(Sender: TObject);
    procedure OpenDesign(const path: AnsiString);
    procedure Relayout(w, h: Integer);
    procedure OnFormResize(Sender: TControl; w, h: Integer);
    procedure OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseMove(Sender: TControl; Button, X, Y: Integer);
    procedure OnDesignMouseUp(Sender: TControl; Button, X, Y: Integer);
    procedure ShowInspector(idx: Integer);
    procedure OnPropClick(Sender: TObject);
    procedure OnValueKey(Sender: TControl; KeyCode: Integer);
    procedure ApplyEdit;
    procedure OnPlaceToggle(Sender: TObject);
  end;

{ palette index -> docmodel kind (Form is the root, never placed) }
function KindFromPalette(idx: Integer): TWidgetKind;
begin
  case idx of
    0: KindFromPalette := wkButton;
    1: KindFromPalette := wkLabel;
    2: KindFromPalette := wkEdit;
    3: KindFromPalette := wkMemo;
    4: KindFromPalette := wkListBox;
    5: KindFromPalette := wkCheckBox;
    6: KindFromPalette := wkPanel;
  else
    KindFromPalette := wkButton;
  end;
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

{ delete the selected node (and its children); the root form is kept }
procedure THandler.OnDelete(Sender: TObject);
begin
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  if Dsn.Sel <= 0 then Exit;   { -1 none, 0 = root form (not deletable) }
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
var out: AnsiString; rc, i: Integer;
begin
  if curFile = '' then begin Output.Text := '(no file selected)'; Exit; end;
  out := RunCapture(PXX_PATH, [curFile, BUILD_OUT], rc);
  Output.Text := '$ compile ' + curFile + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
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
var out: AnsiString; rc: Integer;
begin
  out := RunCapture(BUILD_OUT, [], rc);
  Output.Text := '$ run' + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
end;

procedure THandler.OnUp(Sender: TObject);
begin
  LoadDir(ParentDir(dir));
end;

{ reflow the panes for a content area of w x h (mirrors the startup layout).
  Toolbar widgets stay pinned at the top. }
procedure THandler.Relayout(w, h: Integer);
var cw, ch, contentH: Integer;
begin
  contentH := h - TOOLBAR_H;
  cw := w - W_TREE - W_RIGHT;
  ch := contentH - H_BOTTOM;
  { clamp so panes never collapse to negative / zero on a tiny window }
  if cw < 120 then cw := 120;
  if ch < 80 then ch := 80;
  if contentH < 160 then contentH := 160;

  Tree.SetBounds(0, TOOLBAR_H, W_TREE, contentH - ERR_H);
  Errors.SetBounds(0, TOOLBAR_H + contentH - ERR_H, W_TREE, ERR_H);
  Editor.SetBounds(W_TREE, TOOLBAR_H, cw, ch);
  Output.SetBounds(W_TREE, TOOLBAR_H + ch, cw, contentH - ch);
  DesignBox.SetBounds(W_TREE + cw, TOOLBAR_H, W_RIGHT, ch);
  Props.SetBounds(W_TREE + cw, TOOLBAR_H + ch, W_RIGHT, contentH - ch - 28);
  ValueEdit.SetBounds(W_TREE + cw, TOOLBAR_H + contentH - 28, W_RIGHT, 26);
  DesignBox.Invalidate;
end;

procedure THandler.OnFormResize(Sender: TControl; w, h: Integer);
begin
  Relayout(w, h);
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
end;

procedure THandler.ShowInspector(idx: Integer);
var d: TDocModel;
begin
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

procedure THandler.OnPlaceToggle(Sender: TObject);
begin
  PlaceMode := not PlaceMode;
  if PlaceMode then PlaceBtn.Caption := 'Place*' else PlaceBtn.Caption := 'Place';
end;

procedure THandler.OnDesignMouseDown(Sender: TControl; Button, X, Y: Integer);
var idx: Integer; k: TWidgetKind;
begin
  if PlaceMode then
  begin
    { drop a new widget of the palette kind, parented to the form (node 0) }
    k := KindFromPalette(Palette.ItemIndex);
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
  arg, startDir: AnsiString;
  centerW, centerH, contentH: Integer;
  sbuf: TIdeBuffer;
  sok: Boolean;
  rtdoc: TDocModel;

function MkButton(const cap: AnsiString; x: Integer): TButton;
var b: TButton;
begin
  b := TButton.Create;
  b.Parent := Form1;
  b.Caption := cap;
  b.SetBounds(x, 3, 80, 26);
  MkButton := b;
end;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Eliah - IDE';
  Form1.SetBounds(0, 0, W_WIN, H_WIN);

  contentH := H_WIN - TOOLBAR_H;
  centerW := W_WIN - W_TREE - W_RIGHT;
  centerH := contentH - H_BOTTOM;

  H := THandler.Create;

  H.Tree := TListBox.Create;
  H.Tree.Parent := Form1;
  H.Tree.SetBounds(0, TOOLBAR_H, W_TREE, contentH - ERR_H);
  H.Tree.OnClick := @H.OnTreeClick;

  { error list under the tree: compile diagnostics, click -> jump editor }
  H.Diags := TDiagList.Create;
  H.Errors := TListBox.Create;
  H.Errors.Parent := Form1;
  H.Errors.SetBounds(0, TOOLBAR_H + contentH - ERR_H, W_TREE, ERR_H);
  H.Errors.OnClick := @H.OnErrorClick;

  H.Editor := TMemo.Create;
  H.Editor.Parent := Form1;
  H.Editor.SetBounds(W_TREE, TOOLBAR_H, centerW, centerH);

  H.Output := TMemo.Create;
  H.Output.Parent := Form1;
  H.Output.SetBounds(W_TREE, TOOLBAR_H + centerH, centerW, H_BOTTOM);
  H.Output.Text := 'build output appears here';

  { designer: box-emulated preview painted from the garin docmodel (no live
    widgets). Seed the surface by loading a sample .lfm through the garin loader
    (box-emulation parser, not the live-component streamer). }
  Dsn := TDesigner.Create;
  Dsn.Doc := TDocModel.Create;
  sbuf := TIdeBuffer.Create;
  if sbuf.LoadFromFile(SAMPLE_LFM) then
    sok := LoadLfmText(sbuf.Text, Dsn.Doc);

  DesignBox := TPaintBox.Create;
  DesignBox.Parent := Form1;
  DesignBox.SetBounds(W_TREE + centerW, TOOLBAR_H, W_RIGHT, centerH);
  DesignBox.OnPaint := @Dsn.Paint;
  { mouse-select + drag-move: down hit-tests & grabs, move drags the selected
    box, up releases. }
  DesignBox.OnMouseDown := @H.OnDesignMouseDown;
  DesignBox.OnMouseMove := @H.OnDesignMouseMove;
  DesignBox.OnMouseUp   := @H.OnDesignMouseUp;

  Props := TListBox.Create;
  Props.Parent := Form1;
  Props.SetBounds(W_TREE + centerW, TOOLBAR_H + centerH, W_RIGHT, H_BOTTOM - 28);
  Props.AddItem('object inspector (M1)');
  Props.OnClick := @H.OnPropClick;

  { value editor: pick a prop row above, type here, Enter commits to docmodel }
  ValueEdit := TEdit.Create;
  ValueEdit.Parent := Form1;
  ValueEdit.SetBounds(W_TREE + centerW, TOOLBAR_H + centerH + H_BOTTOM - 28,
    W_RIGHT, 26);
  ValueEdit.OnKeyDown := @H.OnValueKey;

  H.Dsn := Dsn;
  H.DesignBox := DesignBox;
  H.Props := Props;
  H.ValueEdit := ValueEdit;
  H.FEditRow := -1;
  H.designPath := SAMPLE_LFM;   { seeded from the sample; Save targets it until a .lfm is opened }

  Form1.OnResize := @H.OnFormResize;   { reflow panes on window resize }

  btn := MkButton('Up',      4);   btn.OnClick := @H.OnUp;
  btn := MkButton('Compile', 90);  btn.OnClick := @H.OnCompile;
  btn := MkButton('Run',     176); btn.OnClick := @H.OnRun;
  btn := MkButton('Save',    466); btn.OnClick := @H.OnSave;
  btn := MkButton('Del',     552); btn.OnClick := @H.OnDelete;

  { palette: pick a widget kind, hit Place, then click the designer to drop it }
  Palette := TComboBox.Create;
  Palette.Parent := Form1;
  Palette.SetBounds(266, 3, 110, 26);
  Palette.AddItem('Button');
  Palette.AddItem('Label');
  Palette.AddItem('Edit');
  Palette.AddItem('Memo');
  Palette.AddItem('ListBox');
  Palette.AddItem('CheckBox');
  Palette.AddItem('Panel');
  Palette.ItemIndex := 0;

  PlaceBtn := TButton.Create;
  PlaceBtn.Parent := Form1;
  PlaceBtn.Caption := 'Place';
  PlaceBtn.SetBounds(382, 3, 80, 26);
  PlaceBtn.OnClick := @H.OnPlaceToggle;

  H.Palette := Palette;
  H.PlaceBtn := PlaceBtn;
  H.PlaceMode := False;

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if (arg <> '') and (arg <> '--smoke') then startDir := arg else startDir := '.';
  H.LoadDir(startDir);

  Form1.Realize;

  if arg = '--smoke' then
  begin
    if H.nItems < 1 then begin writeln('SMOKE FAIL: empty tree'); Halt(1); end;

    { sample .lfm loaded into the designer docmodel }
    if H.Dsn.Doc.Count <> 5 then begin writeln('SMOKE FAIL: sample.lfm not loaded'); Halt(1); end;
    if H.Dsn.Doc.NodeCaption(3) <> 'OK' then begin writeln('SMOKE FAIL: lfm OK button missing'); Halt(1); end;
    if H.Dsn.Doc.NodeX(3) <> 28 then begin writeln('SMOKE FAIL: lfm abs coord wrong'); Halt(1); end;

    { pane reflow: a bigger window stretches the center/right panes }
    H.Relayout(1400, 900);
    if H.Editor.Width <> 1400 - W_TREE - W_RIGHT then begin writeln('SMOKE FAIL: editor width did not reflow'); Halt(1); end;
    if H.DesignBox.Height <> (900 - TOOLBAR_H - H_BOTTOM) then begin writeln('SMOKE FAIL: designbox height did not reflow'); Halt(1); end;
    { tiny window clamps instead of going negative }
    H.Relayout(200, 120);
    if H.Editor.Width < 120 then begin writeln('SMOKE FAIL: reflow did not clamp width'); Halt(1); end;
    H.Relayout(W_WIN, H_WIN);   { restore }

    { open any .lfm from the tree: clicking a .lfm reloads the designer + retargets Save }
    H.Dsn.Doc := TDocModel.Create;   { wipe to prove OpenDesign reloads }
    H.designPath := '';
    H.OpenDesign('apps/ide/eliah/sample.lfm');
    if H.Dsn.Doc.Count <> 5 then begin writeln('SMOKE FAIL: OpenDesign did not load'); Halt(1); end;
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
    if H.Dsn.Doc.NodeKind(H.Dsn.Sel) <> KindFromPalette(H.Palette.ItemIndex) then
      begin writeln('SMOKE FAIL: placed node wrong kind'); Halt(1); end;
    if H.PlaceMode then begin writeln('SMOKE FAIL: place mode not one-shot'); Halt(1); end;

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

    writeln('SMOKE OK');
  end
  else
  begin
    Application.MainForm := Form1;
    Application.Run;
  end;
end.
