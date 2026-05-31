unit forms;

{ LCL-compatible TForm + TApplication on GTK3. Slice 1: a form is a GTK
  toplevel window; Application.Run wires window-close to quit and enters the
  GTK main loop. No `initialization` sections in the dialect, so the program
  must create Application explicitly before use (see the demo). }

interface

uses controls, gtk3;

type
  TForm = class(TWinControl)
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ApplyCaption; override;
  end;

  TApplication = class
  private
    FMainForm: TForm;
  public
    procedure Initialize;
    procedure Run(mainForm: TForm);
  end;

var
  Application: TApplication;

implementation

{ Static GTK signal handler: window destroyed -> leave the main loop. }
procedure AppDestroy(widget: Pointer; data: Pointer); cdecl;
begin
  gtk_main_quit;
end;

procedure TForm.CreateHandle;
var h: Pointer;
begin
  h := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  Self.Handle := h;
  gtk_window_set_default_size(h, 320, 240);
end;

constructor TForm.Create;
begin
  Self.HandleNeeded;
end;

procedure TForm.ApplyCaption;
var h: Pointer; s: string;
begin
  h := Self.Handle;
  s := Self.Caption;
  gtk_window_set_title(h, PC(s));
end;

procedure TApplication.Initialize;
begin
  gtk_init(nil, nil);
end;

procedure TApplication.Run(mainForm: TForm);
var h: Pointer;
begin
  FMainForm := mainForm;
  mainForm.Realize;                 { build child widgets (streamed forms) }
  h := mainForm.Handle;
  SignalConnect(h, 'destroy', @AppDestroy);
  gtk_widget_show_all(h);
  gtk_main;
end;

end.
