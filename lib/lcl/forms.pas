unit forms;

{ LCL-compatible TForm + TApplication on GTK3.

  A form is a GTK toplevel window. Application.CreateForm instantiates a form
  from a metaclass (class reference), streams its .lfm via RTTI, and remembers
  it as the main form; Application.Run realizes it, wires window-close to quit,
  and enters the GTK main loop. Application itself is created in this unit's
  initialization section (as in real LCL), so a stock program can just use it. }

interface

uses controls, classes_lite, typinfo, lfm, gtk3;

type
  TForm = class(TWinControl)
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ApplyCaption; override;
  end;

  TFormClass = class of TForm;

  TApplication = class
  private
    FMainForm: TForm;
  public
    Scaled: Boolean;            { accepted for LCL source compat (no effect yet) }
    procedure Initialize;
    procedure CreateForm(formClass: TFormClass; var ref: TForm);
    procedure Run;
  end;

var
  Application: TApplication;
  { LCL global toggled by stock .lpr files; accepted, no effect here. }
  RequireDerivedFormResource: Boolean;

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

{ Instantiate a form from its metaclass (PClassRTTI), stream its .lfm by the
  class's runtime name, hand the instance back to the caller's var, and keep it
  as the main form. No constructor is run (CreateInstance just sets the VMT);
  the .lfm + Realize drive the rest, matching the LCL streaming contract. }
procedure TApplication.CreateForm(formClass: TFormClass; var ref: TForm);
var meta: PClassRTTI; inst: TForm; comp: TComponent; nm: string;
begin
  meta := formClass;
  inst := CreateInstance(meta);     { Pointer -> class }
  comp := inst;                     { TForm -> TComponent for the streamer }
  nm := GetClassName(meta);
  InitInheritedComponent(comp, nm);
  ref := inst;
  FMainForm := inst;
end;

procedure TApplication.Run;
var h: Pointer;
begin
  FMainForm.Realize;                { build child widgets (streamed forms) }
  h := FMainForm.Handle;
  SignalConnect(h, 'destroy', @AppDestroy);
  gtk_widget_show_all(h);
  gtk_main;
end;

initialization
  Application := TApplication.Create;
end.
