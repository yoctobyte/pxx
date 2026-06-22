program eliah;

{ Eliah — GTK face of the IDE.

  M0: a single sizable window with a fixed tiled layout — no multi-window, no
  modal forms, no subwindows. Panes:

    +--------+----------------------+-----------+
    | proj   |   editor             | designer  |
    | tree   |                      | (M1 stub) |
    |        +----------------------+-----------+
    |        |   output (M2 stub)   | props     |
    +--------+----------------------+-----------+

  The editor pane is live (loads a file through the garin buffer). The other
  panes are visible stubs filled in by later milestones. }

uses gtk3, controls, stdctrls, forms, buffer;

const
  W_WIN    = 1100;
  H_WIN    = 720;
  W_TREE   = 220;
  W_RIGHT  = 320;
  H_BOTTOM = 170;

var
  Form1: TForm;
  Tree, Props, Designer: TListBox;
  Editor, Output: TMemo;
  Buf: TIdeBuffer;
  centerW, centerH, rightX: Integer;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Eliah - IDE (M0)';
  Form1.SetBounds(0, 0, W_WIN, H_WIN);

  centerW := W_WIN - W_TREE - W_RIGHT;
  centerH := H_WIN - H_BOTTOM;
  rightX  := W_TREE + centerW;

  { left: project tree (stub) }
  Tree := TListBox.Create;
  Tree.Parent := Form1;
  Tree.SetBounds(0, 0, W_TREE, H_WIN);
  Tree.AddItem('apps/ide');
  Tree.AddItem('  garin/');
  Tree.AddItem('  eliah/');
  Tree.AddItem('    main.pas');
  Tree.AddItem('  ilja/');

  { center-top: editor (live) }
  Editor := TMemo.Create;
  Editor.Parent := Form1;
  Editor.SetBounds(W_TREE, 0, centerW, centerH);

  { center-bottom: build output (stub, wired in M2) }
  Output := TMemo.Create;
  Output.Parent := Form1;
  Output.SetBounds(W_TREE, centerH, centerW, H_BOTTOM);
  Output.Text := 'output: build log appears here (M2)';

  { right-top: form designer (stub, box-painting lands in M1) }
  Designer := TListBox.Create;
  Designer.Parent := Form1;
  Designer.SetBounds(rightX, 0, W_RIGHT, centerH);
  Designer.AddItem('designer: box-emulated preview (M1)');
  Designer.AddItem('(no live widgets, no TComponent)');

  { right-bottom: object inspector (stub) }
  Props := TListBox.Create;
  Props.Parent := Form1;
  Props.SetBounds(rightX, centerH, W_RIGHT, H_BOTTOM);
  Props.AddItem('properties');

  { dogfood: show our own source in the editor }
  Buf := TIdeBuffer.Create;
  if Buf.LoadFromFile('apps/ide/eliah/main.pas') then
    Editor.Text := Buf.Text
  else
    Editor.Text := '(could not open apps/ide/eliah/main.pas)';

  Application.MainForm := Form1;
  Application.Run;
end.
