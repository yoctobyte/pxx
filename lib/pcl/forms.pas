{ SPDX-License-Identifier: Zlib }
unit forms;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses controls, classes_lite, typinfo, lfm, interfaces, uwidgetset, menus;

type
  TForm = class(TWinControl)
  private
    FMenu: TMainMenu;
    FClient: TControl;
    FHeaderHeight: Integer;
    procedure SetMenu(v: TMainMenu);
  public
    constructor Create(AOwner: TComponent); override;
    procedure CreateHandle; override;
    function ApplyCaption: Integer; override;
    function Realize: Integer; override;
    { Let AControl fill the window below AHeaderHeight pixels of toolbar, and
      RESIZE WITH IT. Without this a form's children sit at absolute
      coordinates, which is fine for a toolbar and wrong for the thing the user
      drags the window edge to make bigger; see WidgetSet.SetFormClient for why
      an OnResize handler cannot do this job. Re-applied by Realize, because
      Realize re-parents every child. }
    procedure SetClient(AControl: TControl; AHeaderHeight: Integer);
    property Menu: TMainMenu read FMenu write SetMenu;
    property Client: TControl read FClient;
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

{ modal folder picker; returns the chosen path or '' if cancelled.
  Kept here for the callers that predate dialogs.pas' TSelectDirectoryDialog;
  both reach the one seam entry, so there is still only one chooser. }
function SelectFolderDialog(const ATitle: string): string;

implementation

function SelectFolderDialog(const ATitle: string): string;
begin
  SelectFolderDialog := WidgetSet.ChooseFile(cmSelectFolder, ATitle, '', '', '');
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

procedure TForm.SetClient(AControl: TControl; AHeaderHeight: Integer);
begin
  FClient := AControl;
  FHeaderHeight := AHeaderHeight;
  { now if the handles exist, else Realize does it }
  if (Self.Handle <> nil) and (AControl <> nil) and (AControl.Handle <> nil) then
    WidgetSet.SetFormClient(Self, AControl, AHeaderHeight);
end;

function TForm.Realize: Integer;
var dummy: Integer;
begin
  dummy := inherited Realize;
  if FMenu <> nil then
  begin
    dummy := WidgetSet.SetFormMenu(Self, FMenu);
  end;
  { AFTER inherited: Realize walks the children and re-parents each one into the
    form's absolute-coordinate container, so a client set earlier would be put
    back there. Re-applying is cheaper than making SetParent know about it, and
    it is the same shape as the menu above. }
  if FClient <> nil then
    WidgetSet.SetFormClient(Self, FClient, FHeaderHeight);
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
