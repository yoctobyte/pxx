unit forms;

interface

uses controls, classes_lite, typinfo, lfm, interfaces, uwidgetset;

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
    Scaled: Boolean;
    procedure Initialize;
    procedure CreateForm(formClass: TFormClass; var ref: TForm);
    procedure Run;
    property MainForm: TForm read FMainForm write FMainForm;
  end;

var
  Application: TApplication;
  RequireDerivedFormResource: Boolean;

implementation



procedure TForm.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateForm(Self);
  writeln('TForm.CreateHandle: Handle=', Int64(Self.Handle));
end;

constructor TForm.Create;
begin
  Self.HandleNeeded;
end;

procedure TForm.ApplyCaption;
begin
  if Self.Handle <> nil then
    WidgetSet.SetText(Self, Self.Caption);
end;

procedure TApplication.Initialize;
begin
  if WidgetSet = nil then
  begin
    writeln('WidgetSet is NIL!');
    Halt(1);
  end;
  WidgetSet.AppInit;
end;

procedure TApplication.CreateForm(formClass: TFormClass; var ref: TForm);
var meta: PClassRTTI; inst: TForm; comp: TComponent; nm: string;
begin
  meta := formClass;
  inst := CreateInstance(meta);
  comp := inst;
  nm := GetClassName(meta);
  InitInheritedComponent(comp, nm);
  ref := inst;
  if FMainForm = nil then
    FMainForm := inst;
end;

procedure TApplication.Run;
begin
  if FMainForm <> nil then
  begin
    FMainForm.Realize;
    WidgetSet.ConnectAppQuit(FMainForm);
    WidgetSet.ShowWidget(FMainForm);
  end;
  WidgetSet.AppRun;
end;

initialization
  Application := TApplication.Create;
end.
