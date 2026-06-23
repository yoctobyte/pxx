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
     buffer, runner, docmodel, designer, lfmload;

const
  W_WIN     = 1100;
  H_WIN     = 700;
  W_TREE    = 240;
  W_RIGHT   = 300;
  H_BOTTOM  = 200;
  TOOLBAR_H = 34;
  PXX_PATH  = 'stable_linux_amd64/default/pinned';
  BUILD_OUT = '/tmp/eliah_build';
  SAMPLE_LFM = 'apps/ide/eliah/sample.lfm';

type
  THandler = class
    Tree: TListBox;
    Editor, Output: TMemo;
    Props: TListBox;
    ValueEdit: TEdit;
    FEditRow: Integer;     { which inspector row the value edit targets, -1 none }
    Palette: TComboBox;
    PlaceBtn: TButton;
    PlaceMode: Boolean;    { next designer click drops a new widget }
    Dsn: TDesigner;
    DesignBox: TPaintBox;
    dir, curFile: AnsiString;
    paths: array of AnsiString;
    isdirs: array of Boolean;
    nItems: Integer;
    procedure LoadDir(const d: AnsiString);
    procedure OnTreeClick(Sender: TObject);
    procedure OnCompile(Sender: TObject);
    procedure OnRun(Sender: TObject);
    procedure OnUp(Sender: TObject);
    procedure OnSave(Sender: TObject);
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
end;

procedure THandler.OnCompile(Sender: TObject);
var out: AnsiString; rc: Integer;
begin
  if curFile = '' then begin Output.Text := '(no file selected)'; Exit; end;
  out := RunCapture(PXX_PATH, [curFile, BUILD_OUT], rc);
  Output.Text := '$ compile ' + curFile + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
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

{ serialize the designer docmodel back to sample.lfm (round-trips the loader) }
procedure THandler.OnSave(Sender: TObject);
begin
  if (Dsn = nil) or (Dsn.Doc = nil) then Exit;
  if WriteAllText(SAMPLE_LFM, SaveLfmText(Dsn.Doc)) then
    Output.Text := '$ saved ' + SAMPLE_LFM + ' (' + IntToStr(Dsn.Doc.Count) + ' nodes)'
  else
    Output.Text := '$ save failed: ' + SAMPLE_LFM;
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
  H.Tree.SetBounds(0, TOOLBAR_H, W_TREE, contentH);
  H.Tree.OnClick := @H.OnTreeClick;

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

  btn := MkButton('Up',      4);   btn.OnClick := @H.OnUp;
  btn := MkButton('Compile', 90);  btn.OnClick := @H.OnCompile;
  btn := MkButton('Run',     176); btn.OnClick := @H.OnRun;
  btn := MkButton('Save',    466); btn.OnClick := @H.OnSave;

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

    H.LoadDir('apps/ide/garin');
    H.Tree.ItemIndex := H.nItems - 1;
    H.OnTreeClick(nil);
    if Length(H.Editor.Text) = 0 then begin writeln('SMOKE FAIL: editor empty'); Halt(1); end;
    H.curFile := 'apps/ide/garin/buffer.pas';
    H.OnCompile(nil);
    if Length(H.Output.Text) = 0 then begin writeln('SMOKE FAIL: no compile output'); Halt(1); end;

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
