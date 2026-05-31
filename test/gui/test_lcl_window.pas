program test_lcl_window;

{ Slice 1 of the LCL widgetset bridge: build a form + button through the
  LCL-style API (Application/TForm/TButton) and show it via GTK3. A 2s
  timeout quits so the test terminates unattended. Closing the window also
  quits (Application wires "destroy"). No event handlers yet — slice 2. }

uses gtk3, controls, stdctrls, forms;

var
  Form1: TForm;
  Btn: TButton;

function AutoQuit(data: Pointer): Integer; cdecl;
begin
  writeln('auto-quit');
  gtk_main_quit;
  AutoQuit := 0;
end;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'LCL on GTK';

  Btn := TButton.Create;
  Btn.Caption := 'Hello LCL';
  Btn.Parent := Form1;

  g_timeout_add(2000, @AutoQuit, nil);
  Application.Run(Form1);

  writeln('done');
end.
