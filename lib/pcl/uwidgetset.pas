{ SPDX-License-Identifier: Zlib }
unit uwidgetset;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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
    procedure Invalidate(AControl: TComponent); virtual;
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
    procedure MemoCaretToLine(AMemo: TComponent; line: Integer); virtual;
    function MemoCaretLine(AMemo: TComponent): Integer; virtual;

    function AddListItem(AListBox: TComponent; const AText: string): Pointer; virtual;
    function GetListIndex(AListBox: TComponent): Integer; virtual;
    procedure SetListIndex(AListBox: TComponent; AIndex: Integer); virtual;
    procedure ClearList(AListBox: TComponent); virtual;
    procedure DestroyWidget(AWidget: Pointer); virtual;
    function SelectFolder(const ATitle: string): string; virtual;
    
    procedure AddComboItem(AComboBox: TComponent; const AText: string); virtual;
    function GetActiveIndex(AComboBox: TComponent): Integer; virtual;
    procedure SetActiveIndex(AComboBox: TComponent; AIndex: Integer); virtual;
    procedure ClearCombo(AComboBox: TComponent); virtual;
    
    function StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; virtual;
    procedure StopTimer(AId: LongWord); virtual;
    function SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; virtual;

    { ---- the seam, sealed (feature-pcl-seam-seal) ----
      extctrls, dialogs and glarea used to call GTK raw, which meant a second
      widgetset could only ever implement PART of PCL: the leaked widgets would
      silently stay GTK. These are the operations those three units need,
      expressed the way the rest of the seam already is — the widget classes
      hold an opaque Handle and nothing else. }

    { A generic widget, addressed by its handle rather than by its TComponent:
      a paned's child and a notebook's page box are widgets PCL never wrapped
      in a control, so the TComponent-keyed calls above cannot reach them. }
    procedure ShowHandle(AWidget: Pointer); virtual;
    procedure HideHandle(AWidget: Pointer); virtual;
    function HandleWidth(AWidget: Pointer): Integer; virtual;
    function HandleHeight(AWidget: Pointer): Integer; virtual;

    { Paned — a two-child splitter with a draggable divider. }
    function CreatePaned(AVertical: Boolean): Pointer; virtual;
    procedure PanedSetPosition(APaned: Pointer; APos: Integer); virtual;
    function PanedGetPosition(APaned: Pointer): Integer; virtual;
    { pane is 1 or 2; nil when that side is empty }
    function PanedChild(APaned: Pointer; APane: Integer): Pointer; virtual;

    { Box — children packed in order along one axis. }
    function CreateBox(AVertical: Boolean; ASpacing: Integer): Pointer; virtual;
    procedure BoxPack(ABox, AChild: Pointer; AExpand, AFill: Boolean; APadding: Integer); virtual;

    { Notebook — a tab strip. The page label is a STRING here: making the
      caller build a label widget would leak the toolkit again. }
    function CreateNotebook: Pointer; virtual;
    function NotebookAddPage(ANotebook: Pointer; const ACaption: string): Pointer; virtual;
    function NotebookGetPage(ANotebook: Pointer): Integer; virtual;
    procedure NotebookSetPage(ANotebook: Pointer; AIndex: Integer); virtual;

    { A modal message box. Returns when it is dismissed — by the user, or by
      DismissMessageBox from a timer in a test harness. }
    procedure MessageBox(const AText: string); virtual;
    procedure DismissMessageBox; virtual;

  end;

  { ---- the allowed SPARSE point of the seam: OpenGL ----
    GL lives on its own object, not on TWidgetSet, for a measured reason: the
    GL entry points come from a separate shared library, and putting them on
    the main widgetset made EVERY PCL binary carry a DT_NEEDED on it — every
    GUI test failed to start with "libgl_c.so: cannot open shared object
    file". Only a program that actually uses TGLArea should pay that.

    So a widgetset with no GL simply never installs a backend here: the base
    class returns nil from CreateArea and no-ops the rest, which is the honest
    answer rather than a link error or a forced GL implementation. }
  TGLBackend = class
  public
    function CreateArea(AMajor, AMinor: Integer): Pointer; virtual;
    procedure MakeCurrent(AArea: Pointer); virtual;
    procedure QueueRender(AArea: Pointer); virtual;
    { The render and resize callbacks. Their C signatures are the toolkit's —
      which is exactly why this is the sparse point and not part of the seam. }
    procedure OnRender(AArea, ACallback, AData: Pointer); virtual;
    procedure OnResize(AArea, ACallback, AData: Pointer); virtual;
  end;

var
  WidgetSet: TWidgetSet;
  { nil until a GL-capable widgetset unit installs one; TGLArea checks. }
  GLBackend: TGLBackend;

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
procedure TWidgetSet.Invalidate(AControl: TComponent); begin end;
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
procedure TWidgetSet.MemoCaretToLine(AMemo: TComponent; line: Integer); begin end;
function TWidgetSet.MemoCaretLine(AMemo: TComponent): Integer; begin MemoCaretLine := 0; end;

function TWidgetSet.AddListItem(AListBox: TComponent; const AText: string): Pointer; begin AddListItem := nil; end;
function TWidgetSet.GetListIndex(AListBox: TComponent): Integer; begin GetListIndex := -1; end;
procedure TWidgetSet.SetListIndex(AListBox: TComponent; AIndex: Integer); begin end;
procedure TWidgetSet.ClearList(AListBox: TComponent); begin end;
procedure TWidgetSet.DestroyWidget(AWidget: Pointer); begin end;
function TWidgetSet.SelectFolder(const ATitle: string): string; begin SelectFolder := ''; end;

procedure TWidgetSet.AddComboItem(AComboBox: TComponent; const AText: string); begin end;
  function TWidgetSet.GetActiveIndex(AComboBox: TComponent): Integer; begin GetActiveIndex := -1; end;
procedure TWidgetSet.SetActiveIndex(AComboBox: TComponent; AIndex: Integer); begin end;
procedure TWidgetSet.ClearCombo(AComboBox: TComponent); begin end;

function TWidgetSet.StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; begin StartTimer := 0; end;
procedure TWidgetSet.StopTimer(AId: LongWord); begin end;
function TWidgetSet.SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; begin SetFormMenu := 0; end;


{ ---- the sealed seam: base no-ops ----
  A widgetset that does not implement one of these degrades to "nothing
  happens" rather than to a link error, exactly as the calls above do. }
procedure TWidgetSet.ShowHandle(AWidget: Pointer); begin end;
procedure TWidgetSet.HideHandle(AWidget: Pointer); begin end;
function TWidgetSet.HandleWidth(AWidget: Pointer): Integer; begin HandleWidth := 0; end;
function TWidgetSet.HandleHeight(AWidget: Pointer): Integer; begin HandleHeight := 0; end;

function TWidgetSet.CreatePaned(AVertical: Boolean): Pointer; begin CreatePaned := nil; end;
procedure TWidgetSet.PanedSetPosition(APaned: Pointer; APos: Integer); begin end;
function TWidgetSet.PanedGetPosition(APaned: Pointer): Integer; begin PanedGetPosition := 0; end;
function TWidgetSet.PanedChild(APaned: Pointer; APane: Integer): Pointer; begin PanedChild := nil; end;

function TWidgetSet.CreateBox(AVertical: Boolean; ASpacing: Integer): Pointer; begin CreateBox := nil; end;
procedure TWidgetSet.BoxPack(ABox, AChild: Pointer; AExpand, AFill: Boolean; APadding: Integer); begin end;

function TWidgetSet.CreateNotebook: Pointer; begin CreateNotebook := nil; end;
function TWidgetSet.NotebookAddPage(ANotebook: Pointer; const ACaption: string): Pointer; begin NotebookAddPage := nil; end;
function TWidgetSet.NotebookGetPage(ANotebook: Pointer): Integer; begin NotebookGetPage := 0; end;
procedure TWidgetSet.NotebookSetPage(ANotebook: Pointer; AIndex: Integer); begin end;

procedure TWidgetSet.MessageBox(const AText: string); begin end;
procedure TWidgetSet.DismissMessageBox; begin end;


function TGLBackend.CreateArea(AMajor, AMinor: Integer): Pointer; begin CreateArea := nil; end;
procedure TGLBackend.MakeCurrent(AArea: Pointer); begin end;
procedure TGLBackend.QueueRender(AArea: Pointer); begin end;
procedure TGLBackend.OnRender(AArea, ACallback, AData: Pointer); begin end;
procedure TGLBackend.OnResize(AArea, ACallback, AData: Pointer); begin end;

end.
