program test_pcl_window;

{ Slice 1 of the LCL widgetset bridge: build a form + button through the
  PCL-style API (Application/TForm/TButton) and show it via GTK3. A 2s
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
  writeln('starting');
  Application := TApplication.Create;
  writeln('created app');
  Application.Initialize;
  writeln('initialized app');

  Form1 := TForm.Create;
  writeln('created form');
  Form1.Caption := 'PCL on GTK';

  Btn := TButton.Create;
  writeln('created button');
  Btn.Caption := 'Hello PCL';
  Btn.Parent := Form1;

  Application.MainForm := Form1;
  g_timeout_add(2000, @AutoQuit, nil);
  writeln('added timeout');
  Application.Run;

  writeln('done');
end.
