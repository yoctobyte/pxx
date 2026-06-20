unit uwidgetset;

interface

uses classes_lite;

type
  TWidgetSet = class
  public
    procedure AppInit; virtual;
    procedure AppRun; virtual;
    procedure AppQuit; virtual;
    
    function CreateForm(AForm: TComponent): Pointer; virtual;
    function CreateButton(AButton: TComponent): Pointer; virtual;
    function CreateLabel(ALabel: TComponent): Pointer; virtual;
    function CreateEdit(AEdit: TComponent): Pointer; virtual;
    function CreateCheckBox(ACheckBox: TComponent): Pointer; virtual;
    function CreatePanel(APanel: TComponent): Pointer; virtual;
    function CreateMemo(AMemo: TComponent): Pointer; virtual;
    function CreateListBox(AListBox: TComponent): Pointer; virtual;
    function CreateComboBox(AComboBox: TComponent): Pointer; virtual;
    function CreatePaintBox(APaintBox: TComponent): Pointer; virtual;
    
    procedure SetText(AControl: TComponent; const AText: string); virtual;
    procedure SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer); virtual;
    procedure SetParent(AControl: TComponent; AParent: TComponent); virtual;
    procedure ShowWidget(AControl: TComponent); virtual;
    
    procedure ConnectClick(AControl: TComponent); virtual;
    procedure ConnectChange(AControl: TComponent); virtual;
    procedure ConnectAppQuit(AForm: TComponent); virtual;
    
    procedure SetChecked(AControl: TComponent; AChecked: Boolean); virtual;
    function GetChecked(AControl: TComponent): Boolean; virtual;
    
    function GetMemoText(AMemo: TComponent): string; virtual;
    procedure SetMemoText(AMemo: TComponent; const AText: string); virtual;
    
    function AddListItem(AListBox: TComponent; const AText: string): Pointer; virtual;
    function GetListIndex(AListBox: TComponent): Integer; virtual;
    procedure SetListIndex(AListBox: TComponent; AIndex: Integer); virtual;
    procedure ClearList(AListBox: TComponent); virtual;
    procedure DestroyWidget(AWidget: Pointer); virtual;
    
    procedure AddComboItem(AComboBox: TComponent; const AText: string); virtual;
    function GetActiveIndex(AComboBox: TComponent): Integer; virtual;
    procedure SetActiveIndex(AComboBox: TComponent; AIndex: Integer); virtual;
    procedure ClearCombo(AComboBox: TComponent); virtual;
    
    function StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; virtual;
    procedure StopTimer(AId: LongWord); virtual;
    function SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; virtual;
  end;

var
  WidgetSet: TWidgetSet;

implementation

procedure TWidgetSet.AppInit; begin end;
procedure TWidgetSet.AppRun; begin end;
procedure TWidgetSet.AppQuit; begin end;

function TWidgetSet.CreateForm(AForm: TComponent): Pointer; begin CreateForm := nil; end;
function TWidgetSet.CreateButton(AButton: TComponent): Pointer; begin CreateButton := nil; end;
function TWidgetSet.CreateLabel(ALabel: TComponent): Pointer; begin CreateLabel := nil; end;
function TWidgetSet.CreateEdit(AEdit: TComponent): Pointer; begin CreateEdit := nil; end;
function TWidgetSet.CreateCheckBox(ACheckBox: TComponent): Pointer; begin CreateCheckBox := nil; end;
function TWidgetSet.CreatePanel(APanel: TComponent): Pointer; begin CreatePanel := nil; end;
function TWidgetSet.CreateMemo(AMemo: TComponent): Pointer; begin CreateMemo := nil; end;
function TWidgetSet.CreateListBox(AListBox: TComponent): Pointer; begin CreateListBox := nil; end;
function TWidgetSet.CreateComboBox(AComboBox: TComponent): Pointer; begin CreateComboBox := nil; end;
function TWidgetSet.CreatePaintBox(APaintBox: TComponent): Pointer; begin CreatePaintBox := nil; end;

procedure TWidgetSet.SetText(AControl: TComponent; const AText: string); begin end;
procedure TWidgetSet.SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer); begin end;
procedure TWidgetSet.SetParent(AControl: TComponent; AParent: TComponent); begin end;
procedure TWidgetSet.ShowWidget(AControl: TComponent); begin end;

procedure TWidgetSet.ConnectClick(AControl: TComponent); begin end;
procedure TWidgetSet.ConnectChange(AControl: TComponent); begin end;
procedure TWidgetSet.ConnectAppQuit(AForm: TComponent); begin end;

procedure TWidgetSet.SetChecked(AControl: TComponent; AChecked: Boolean); begin end;
function TWidgetSet.GetChecked(AControl: TComponent): Boolean; begin GetChecked := False; end;

function TWidgetSet.GetMemoText(AMemo: TComponent): string; begin GetMemoText := ''; end;
procedure TWidgetSet.SetMemoText(AMemo: TComponent; const AText: string); begin end;

function TWidgetSet.AddListItem(AListBox: TComponent; const AText: string): Pointer; begin AddListItem := nil; end;
function TWidgetSet.GetListIndex(AListBox: TComponent): Integer; begin GetListIndex := -1; end;
procedure TWidgetSet.SetListIndex(AListBox: TComponent; AIndex: Integer); begin end;
procedure TWidgetSet.ClearList(AListBox: TComponent); begin end;
procedure TWidgetSet.DestroyWidget(AWidget: Pointer); begin end;

procedure TWidgetSet.AddComboItem(AComboBox: TComponent; const AText: string); begin end;
  function TWidgetSet.GetActiveIndex(AComboBox: TComponent): Integer; begin GetActiveIndex := -1; end;
procedure TWidgetSet.SetActiveIndex(AComboBox: TComponent; AIndex: Integer); begin end;
procedure TWidgetSet.ClearCombo(AComboBox: TComponent); begin end;

function TWidgetSet.StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; begin StartTimer := 0; end;
procedure TWidgetSet.StopTimer(AId: LongWord); begin end;
function TWidgetSet.SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; begin SetFormMenu := 0; end;

end.
