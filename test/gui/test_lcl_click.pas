program test_lcl_click;

{ Slice 2: button OnClick events. Builds a form + button, assigns a plain
  procedure(Sender) as OnClick, then fires gtk_button_clicked synchronously
  twice. GTK emits "clicked" -> our static trampoline -> CallEvent -> handler.
  Deterministic, no main loop. Expected: two "clicked" lines, count 1 then 2. }

uses gtk3, controls, stdctrls, forms;

var
  Form1: TForm;
  Btn: TButton;
  clicks: Integer;

procedure OnBtnClick(Sender: TObject);
begin
  clicks := clicks + 1;
  writeln('clicked! count=', clicks);
end;

begin
  clicks := 0;
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Click test';

  Btn := TButton.Create;
  Btn.Caption := 'Click me';
  Btn.Parent := Form1;
  Btn.OnClick := @OnBtnClick;

  gtk_button_clicked(Btn.Handle);
  gtk_button_clicked(Btn.Handle);

  writeln('done, total clicks=', clicks);
end.
