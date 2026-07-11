program test_pcl_tabbar;

{ TTabBar (feature-eliah-component-tabbar): a GtkNotebook of horizontal button
  rows. Build two tabs, drop buttons in each, check tab bookkeeping and that a
  tab button's OnClick fires through the normal trampoline
  (gtk_button_clicked, synchronous — same discipline as test_pcl_click). }

uses gtk3, controls, stdctrls, extctrls, forms;

type
  THandler = class
    last: Integer;
    procedure PickA(Sender: TObject);
    procedure PickB(Sender: TObject);
  end;

procedure THandler.PickA(Sender: TObject);
begin
  Self.last := 1;
  writeln('picked A');
end;

procedure THandler.PickB(Sender: TObject);
begin
  Self.last := 2;
  writeln('picked B');
end;

var
  Form1: TForm;
  Bar: TTabBar;
  bA, bB: TButton;
  h: THandler;
  tStd, tNv: Integer;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'TabBar test';

  Bar := TTabBar.Create(nil);
  Bar.Parent := Form1;
  Bar.SetBounds(0, 0, 400, 64);

  tStd := Bar.AddTab('Standard');
  tNv := Bar.AddTab('Non-visual');
  writeln('tabs=', Bar.TabCount);
  writeln('idx=', tStd, ',', tNv);

  h := THandler.Create;
  bA := Bar.AddButton(tStd, 'Btn', @h.PickA);
  bB := Bar.AddButton(tNv, 'Tmr', @h.PickB);
  if Bar.AddButton(99, 'x', @h.PickA) = nil then
    writeln('bad-tab=nil');

  gtk_button_clicked(bA.Handle);
  gtk_button_clicked(bB.Handle);
  writeln('last=', h.last);

  Bar.SetActiveTab(tNv);
  writeln('active=', Bar.ActiveTab);
end.
