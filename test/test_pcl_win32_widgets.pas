{ SPDX-License-Identifier: Zlib }
program test_pcl_win32_widgets;
{ The PCL controls through the Win32 widgetset (lib/pcl/win32widgets.pas),
  built with --os=windows and run under Wine on a virtual X server: a form
  with a button, label, edit, check box, memo, list box and combo box. Text,
  check state and selections are set through PCL and read back from the
  native controls; then the real message loop runs until a TTimer, on its
  second tick, stops itself and calls Application.Terminate. The Linux build
  of the same file (GTK) prints the same lines. }

{$define PXX_MANAGED_STRING}

uses controls, stdctrls, forms, extctrls, sysutils;

type
  TH = class
    clicks, ticks: Integer;
    btn: TButton;
    procedure Click(Sender: TObject);
    procedure Tick(Sender: TObject);
  end;

procedure TH.Click(Sender: TObject);
begin
  clicks := clicks + 1;
end;

procedure TH.Tick(Sender: TObject);
begin
  ticks := ticks + 1;
  if ticks = 2 then
  begin
    TTimer(Sender).Enabled := False;
    Application.Terminate;
  end;
end;

var
  f: TForm; b: TButton; l: TLabel; e: TEdit; c: TCheckBox; m: TMemo;
  lb: TListBox; cb: TComboBox; t: TTimer; h: TH; pm: TMethod;
begin
  Application.Initialize;
  f := TForm.Create(nil);
  f.Caption := 'pcl widgets';
  f.SetBounds(0, 0, 400, 300);
  h := TH.Create;
  b := TButton.Create(f); b.Parent := f; b.Caption := 'Press'; b.SetBounds(10, 10, 80, 26);
  pm.Code := @h.Click; pm.Data := h; b.OnClick := pm;
  l := TLabel.Create(f); l.Parent := f; l.Caption := 'grüße'; l.SetBounds(100, 14, 120, 20);
  e := TEdit.Create(f); e.Parent := f; e.SetBounds(10, 44, 150, 24);
  c := TCheckBox.Create(f); c.Parent := f; c.Caption := 'check'; c.SetBounds(170, 44, 100, 24);
  m := TMemo.Create(f); m.Parent := f; m.SetBounds(10, 76, 200, 80);
  lb := TListBox.Create(f); lb.Parent := f; lb.SetBounds(220, 76, 160, 80);
  cb := TComboBox.Create(f); cb.Parent := f; cb.SetBounds(10, 166, 150, 24);
  f.Realize;
  Application.MainForm := f;

  e.Text := 'edit text';
  writeln('edit ', e.Text);
  c.Checked := True;
  writeln('checked ', c.Checked);
  m.Text := 'one'#10'two'#10'three';
  writeln('memo ', Length(m.Text), ' ', Pos('two', m.Text));
  lb.AddItem('alpha'); lb.AddItem('beta'); lb.AddItem('gamma');
  lb.ItemIndex := 1;
  writeln('list index ', lb.ItemIndex);
  cb.AddItem('x'); cb.AddItem('y');
  cb.ItemIndex := 1;
  writeln('combo index ', cb.ItemIndex, ' ', cb.Item(1));
  lb.Clear; lb.AddItem('delta');
  writeln('list after clear ', lb.Count, ' ', lb.Item(0));

  t := TTimer.Create(nil);
  t.Interval := 150;
  pm.Code := @h.Tick; pm.Data := h; t.OnTimer := pm;
  t.Enabled := True;
  Application.Run;
  writeln('ticks ', h.ticks);
  writeln('done');
end.
