unit forms;

interface

uses controls, classes_lite, typinfo, lfm, interfaces, uwidgetset, menus;

type
  TForm = class(TWinControl)
  private
    FMenu: TMainMenu;
    procedure SetMenu(v: TMainMenu);
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
    function ApplyCaption: Integer; override;
    function Realize: Integer; override;
    property Menu: TMainMenu read FMenu write SetMenu;
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

{ modal folder picker; returns the chosen path or '' if cancelled }
function SelectFolderDialog(const ATitle: string): string;

implementation

function SelectFolderDialog(const ATitle: string): string;
begin
  SelectFolderDialog := WidgetSet.SelectFolder(ATitle);
end;

procedure TForm.SetMenu(v: TMainMenu);
begin
  FMenu := v;
  if FHandle <> nil then
  begin
    WidgetSet.SetFormMenu(Self, v);
  end;
end;

procedure TForm.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateForm(Self);
  if FMenu <> nil then
    WidgetSet.SetFormMenu(Self, FMenu);
end;

constructor TForm.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Self.HandleNeeded;
end;

function TForm.ApplyCaption: Integer;
begin
  if Self.Handle <> nil then
    WidgetSet.SetText(Self, Self.Caption);
  Result := 0;
end;

function TForm.Realize: Integer;
var dummy: Integer;
begin
  dummy := inherited Realize;
  if FMenu <> nil then
  begin
    dummy := WidgetSet.SetFormMenu(Self, FMenu);
  end;
  Result := 0;
end;

procedure TApplication.Initialize;
begin
  if WidgetSet = nil then
  begin
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
