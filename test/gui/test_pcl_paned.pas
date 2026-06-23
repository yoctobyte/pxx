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

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Paned Test';
  Form1.SetBounds(0, 0, 400, 300);

  { outer vertical paned fills the form }
  VSplit := TPaned.Create(nil);
  VSplit.Vertical := True;
  VSplit.Parent := Form1;
  VSplit.SetBounds(0, 0, 400, 300);

  { pane 1 of the vertical split is itself a horizontal split of two panels }
  HSplit := TPaned.Create(nil);            { horizontal (default) }
  HSplit.Parent := VSplit;

  TopL := TPanel.Create(nil);
  TopL.Parent := HSplit;
  TopR := TPanel.Create(nil);
  TopR.Parent := HSplit;

  { pane 2 of the vertical split is a single panel }
  BottomP := TPanel.Create(nil);
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

  { collapse pane 1 to a 16px strip, then restore to the remembered position }
  HSplit.Position := 150;
  HSplit.Collapse(1, 16);
  if HSplit.CollapsedPane <> 1 then begin writeln('FAIL: not marked collapsed'); Halt(1); end;
  if HSplit.ActualPosition <> 16 then begin writeln('FAIL: collapse did not shrink to strip'); Halt(1); end;
  HSplit.Restore;
  if HSplit.CollapsedPane <> 0 then begin writeln('FAIL: still marked collapsed'); Halt(1); end;
  if HSplit.ActualPosition <> 150 then begin writeln('FAIL: restore did not return to remembered pos'); Halt(1); end;

  { Toggle: collapse then restore via the same call }
  HSplit.Toggle(1, 0);
  if HSplit.CollapsedPane <> 1 then begin writeln('FAIL: toggle did not collapse'); Halt(1); end;
  HSplit.Toggle(1, 0);
  if HSplit.CollapsedPane <> 0 then begin writeln('FAIL: toggle did not restore'); Halt(1); end;
  if HSplit.ActualPosition <> 150 then begin writeln('FAIL: toggle restore pos wrong'); Halt(1); end;

  writeln('PASS: TPaned splits, packs two children each, position + collapse/restore');
end.
