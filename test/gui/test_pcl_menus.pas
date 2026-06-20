program test_pcl_menus;

uses gtk3, gtk3_c, controls, menus, forms, classes_lite, uwidgetset, gtk3widgets;

var
  Form1: TForm;
  MainMenu1: TMainMenu;
  FileMenu, EditMenu, NewItem, ExitItem: TMenuItem;
  ExitClicked: Boolean;

type
  TTestHelper = class
    procedure ExitClick(Sender: Pointer);
  end;

procedure TTestHelper.ExitClick(Sender: Pointer);
begin
  writeln('ExitItem clicked!');
  ExitClicked := True;
end;

var
  Helper: TTestHelper;
  m: TMethod;
  dummy: Integer;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Menus Test';

  MainMenu1 := TMainMenu.Create;
  Form1.Menu := MainMenu1;

  FileMenu := TMenuItem.Create;
  FileMenu.Caption := '&File';
  MainMenu1.Items.Add(FileMenu);

  NewItem := TMenuItem.Create;
  NewItem.Caption := '&New';
  FileMenu.Add(NewItem);

  ExitItem := TMenuItem.Create;
  ExitItem.Caption := 'E&xit';
  
  Helper := TTestHelper.Create;
  m.Code := @Helper.ExitClick;
  m.Data := Helper;
  ExitItem.OnClick := m;
  FileMenu.Add(ExitItem);

  EditMenu := TMenuItem.Create;
  EditMenu.Caption := '&Edit';
  MainMenu1.Items.Add(EditMenu);

  ExitClicked := False;

  writeln('Realizing form and menus...');
  dummy := Form1.Realize;
  dummy := TGtk3WidgetSet(WidgetSet).SetFormMenu(Form1, MainMenu1);

  writeln('Checking Menu structure...');
  if MainMenu1.Items.Count <> 2 then
  begin
    writeln('FAIL: MainMenu top-level items count mismatch. Expected 2, got ', MainMenu1.Items.Count);
    Halt(1);
  end;

  if FileMenu.Count <> 2 then
  begin
    writeln('FAIL: FileMenu sub-items count mismatch. Expected 2, got ', FileMenu.Count);
    Halt(1);
  end;

  writeln('Checking GTK widget handles...');
  if FileMenu.Handle = nil then
  begin
    writeln('FAIL: FileMenu widget handle is nil');
    Halt(1);
  end;

  if ExitItem.Handle = nil then
  begin
    writeln('FAIL: ExitItem widget handle is nil');
    Halt(1);
  end;

  writeln('Simulating menu item activation...');
  gtk_menu_item_activate(ExitItem.Handle);

  if not ExitClicked then
  begin
    writeln('FAIL: ExitItem click handler was not triggered');
    Halt(1);
  end;

  writeln('ALL MENU TESTS PASSED');
end.
