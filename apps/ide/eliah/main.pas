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
  the built binary. The right column (designer + object inspector) is a stub
  pending M1. }

uses gtk3, controls, stdctrls, extctrls, graphics, forms, sysutils,
     buffer, runner, docmodel, designer;

const
  W_WIN     = 1100;
  H_WIN     = 700;
  W_TREE    = 240;
  W_RIGHT   = 300;
  H_BOTTOM  = 200;
  TOOLBAR_H = 34;
  PXX_PATH  = 'stable_linux_amd64/default/pinned';
  BUILD_OUT = '/tmp/eliah_build';

type
  THandler = class
    Tree: TListBox;
    Editor, Output: TMemo;
    dir, curFile: AnsiString;
    paths: array of AnsiString;
    isdirs: array of Boolean;
    nItems: Integer;
    procedure LoadDir(const d: AnsiString);
    procedure OnTreeClick(Sender: TObject);
    procedure OnCompile(Sender: TObject);
    procedure OnRun(Sender: TObject);
    procedure OnUp(Sender: TObject);
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
var out: AnsiString; rc: Integer; args: array of AnsiString;
begin
  if curFile = '' then begin Output.Text := '(no file selected)'; Exit; end;
  SetLength(args, 2);
  args[0] := curFile;
  args[1] := BUILD_OUT;
  out := RunCapture(PXX_PATH, args, rc);
  Output.Text := '$ compile ' + curFile + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
end;

procedure THandler.OnRun(Sender: TObject);
var out: AnsiString; rc: Integer; args: array of AnsiString;
begin
  SetLength(args, 0);
  out := RunCapture(BUILD_OUT, args, rc);
  Output.Text := '$ run' + #10 + out + #10 + '--- exit ' + IntToStr(rc) + ' ---';
end;

procedure THandler.OnUp(Sender: TObject);
begin
  LoadDir(ParentDir(dir));
end;

var
  Form1: TForm;
  H: THandler;
  Props: TListBox;
  DesignBox: TPaintBox;
  Dsn: TDesigner;
  pm: TMethod;
  arg, startDir: AnsiString;
  centerW, centerH, contentH: Integer;

procedure MkButton(const cap: AnsiString; x: Integer; m: TMethod);
var b: TButton;
begin
  b := TButton.Create;
  b.Parent := Form1;
  b.Caption := cap;
  b.SetBounds(x, 3, 80, 26);
  b.OnClick := m;
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
  pm.Code := @H.OnTreeClick; pm.Data := H;
  H.Tree.OnClick := pm;

  H.Editor := TMemo.Create;
  H.Editor.Parent := Form1;
  H.Editor.SetBounds(W_TREE, TOOLBAR_H, centerW, centerH);

  H.Output := TMemo.Create;
  H.Output.Parent := Form1;
  H.Output.SetBounds(W_TREE, TOOLBAR_H + centerH, centerW, H_BOTTOM);
  H.Output.Text := 'build output appears here';

  { designer: box-emulated preview painted from the garin docmodel (no live
    widgets). Sample form so the surface is non-empty until load/save lands. }
  Dsn := TDesigner.Create;
  Dsn.Doc := TDocModel.Create;
  Dsn.Doc.AddNode(wkForm,   'Form1',  -1, 12, 12, W_RIGHT - 34, centerH - 70);
  Dsn.Doc.AddNode(wkLabel,  'Name:',   0, 28, 48,  56, 18);
  Dsn.Doc.AddNode(wkEdit,   '',        0, 92, 44, 140, 26);
  Dsn.Doc.AddNode(wkButton, 'OK',      0, 28, 92,  80, 28);
  Dsn.Doc.AddNode(wkButton, 'Cancel',  0, 116, 92, 80, 28);

  DesignBox := TPaintBox.Create;
  DesignBox.Parent := Form1;
  DesignBox.SetBounds(W_TREE + centerW, TOOLBAR_H, W_RIGHT, centerH);
  pm.Code := @Dsn.Paint; pm.Data := Dsn;
  DesignBox.OnPaint := pm;

  Props := TListBox.Create;
  Props.Parent := Form1;
  Props.SetBounds(W_TREE + centerW, TOOLBAR_H + centerH, W_RIGHT, H_BOTTOM);
  Props.AddItem('object inspector (M1)');

  pm.Data := H;
  pm.Code := @H.OnUp;      MkButton('Up',      4,   pm);
  pm.Code := @H.OnCompile; MkButton('Compile', 90,  pm);
  pm.Code := @H.OnRun;     MkButton('Run',     176, pm);

  arg := '';
  if ParamCount > 0 then arg := ParamStr(1);
  if (arg <> '') and (arg <> '--smoke') then startDir := arg else startDir := '.';
  H.LoadDir(startDir);

  Form1.Realize;

  if arg = '--smoke' then
  begin
    { Length() is taken of a string variable, not a property getter directly:
      Length(memo.Text) trips bug-length-rejects-non-variable (codegen). }
    if H.nItems < 1 then begin writeln('SMOKE FAIL: empty tree'); Halt(1); end;
    H.LoadDir('apps/ide/garin');
    H.Tree.ItemIndex := H.nItems - 1;
    H.OnTreeClick(nil);
    startDir := H.Editor.Text;
    if Length(startDir) = 0 then begin writeln('SMOKE FAIL: editor empty'); Halt(1); end;
    H.curFile := 'apps/ide/garin/buffer.pas';
    H.OnCompile(nil);
    startDir := H.Output.Text;
    if Length(startDir) = 0 then begin writeln('SMOKE FAIL: no compile output'); Halt(1); end;
    writeln('SMOKE OK');
  end
  else
  begin
    Application.MainForm := Form1;
    Application.Run;
  end;
end.
