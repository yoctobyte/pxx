program test_lcl_click;

{ Slice 2b: `of object` method-pointer events. A handler object's method is
  assigned to the button's OnClick via @obj.method (a TMethod, Code+Data).
  gtk_button_clicked fires synchronously: GTK "clicked" -> static trampoline
  -> CallMethod(Code, Data=handler, Sender=button) -> THandler.Clicked runs
  with Self = the handler. Deterministic; expected count 1 then 2. }

uses gtk3, controls, stdctrls, forms;

type
  THandler = class
    count: Integer;
    procedure Clicked(Sender: TObject);
  end;

procedure THandler.Clicked(Sender: TObject);
begin
  Self.count := Self.count + 1;
  writeln('method click! count=', Self.count);
end;

var
  Form1: TForm;
  Btn: TButton;
  h: THandler;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Click test';

  Btn := TButton.Create;
  Btn.Caption := 'Click me';
  Btn.Parent := Form1;

  h := THandler.Create;
  Btn.OnClick := @h.Clicked;

  gtk_button_clicked(Btn.Handle);
  gtk_button_clicked(Btn.Handle);

  writeln('done, total clicks=', h.count);
end.
