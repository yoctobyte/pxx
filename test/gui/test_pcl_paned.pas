program test_pcl_paned;

{ TPaned — draggable splitter container. Builds a form holding a horizontal
  paned (two panels) nested inside one pane of a vertical paned, realizes it,
  and checks the handle position round-trips through the widget. Headless: it
  constructs + realizes, never enters the main loop. }

uses gtk3, controls, stdctrls, extctrls, forms;

var
  Form1: TForm;
  VSplit: TPaned;
  HSplit: TPaned;
  TopL, TopR, BottomP: TPanel;
  pos: Integer;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Paned Test';
  Form1.SetBounds(0, 0, 400, 300);

  { outer vertical paned fills the form }
  VSplit := TPaned.Create;
  VSplit.Vertical := True;
  VSplit.Parent := Form1;
  VSplit.SetBounds(0, 0, 400, 300);

  { pane 1 of the vertical split is itself a horizontal split of two panels }
  HSplit := TPaned.Create;            { horizontal (default) }
  HSplit.Parent := VSplit;

  TopL := TPanel.Create;
  TopL.Parent := HSplit;
  TopR := TPanel.Create;
  TopR.Parent := HSplit;

  { pane 2 of the vertical split is a single panel }
  BottomP := TPanel.Create;
  BottomP.Parent := VSplit;

  VSplit.Position := 180;
  HSplit.Position := 150;

  Form1.Realize;

  pos := VSplit.ActualPosition;
  writeln('VSplit position: ', pos);
  if pos <> 180 then begin writeln('FAIL: VSplit position mismatch'); Halt(1); end;

  pos := HSplit.ActualPosition;
  writeln('HSplit position: ', pos);
  if pos <> 150 then begin writeln('FAIL: HSplit position mismatch'); Halt(1); end;

  { reposition after realize must take immediately }
  VSplit.Position := 120;
  if VSplit.ActualPosition <> 120 then
  begin writeln('FAIL: VSplit reposition mismatch'); Halt(1); end;

  writeln('PASS: TPaned splits, packs two children each, position round-trips');
end.
