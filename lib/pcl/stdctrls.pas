{$define PXX_MANAGED_STRING}
unit stdctrls;

interface

uses controls, uwidgetset, classes_lite, typinfo;

type
  TButton = class(TWinControl)
  public
    constructor Create;
    procedure CreateHandle; override;
  end;

  TLabel = class(TControl)
  public
    constructor Create;
    procedure CreateHandle; override;
  end;

  TEdit = class(TWinControl)
  private
    FText: string;
    FOnChange: TMethod;
    procedure SetText(const s: string);
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ConnectChange;
  published
    property Text: string read FText write SetText;
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

  TCheckBox = class(TWinControl)
  private
    FChecked: Boolean;
    FOnChange: TMethod;
    procedure SetChecked(v: Boolean);
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ConnectChange;
  published
    property Checked: Boolean read FChecked write SetChecked;
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

  TMemo = class(TWinControl)
  private
    FOnChange: TMethod;
    function GetText: string;
    procedure SetText(const s: string);
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ConnectChange;
  published
    property Text: string read GetText write SetText;
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

  TListBox = class(TWinControl)
  private
    FItems: array of string;
    FRows: array of Pointer;
    FCount: Integer;
    FOnChange: TMethod;
    function GetItemIndex: Integer;
    procedure SetItemIndex(v: Integer);
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ConnectChange;
    procedure AddItem(const s: string);
    procedure Clear;
    function Item(AIndex: Integer): string;
    property Count: Integer read FCount;
  published
    property ItemIndex: Integer read GetItemIndex write SetItemIndex;
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

  TComboBox = class(TWinControl)
  private
    FItems: array of string;
    FCount: Integer;
    FOnChange: TMethod;
    function GetItemIndex: Integer;
    procedure SetItemIndex(v: Integer);
    function GetText: string;
    procedure SetText(const s: string);
  public
    constructor Create;
    procedure CreateHandle; override;
    procedure ConnectChange;
    procedure AddItem(const s: string);
    procedure Clear;
    function Item(AIndex: Integer): string;
    property Count: Integer read FCount;
  published
    property ItemIndex: Integer read GetItemIndex write SetItemIndex;
    property Text: string read GetText write SetText;
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

implementation

procedure ZeroMemory(p: Pointer; size: Integer);
var
  pb: ^Byte;
  i: Integer;
begin
  pb := p;
  for i := 0 to size - 1 do
  begin
    pb^ := 0;
    pb := pb + 1;
  end;
end;

{ TButton }

constructor TButton.Create;
begin
  Self.HandleNeeded;
end;

procedure TButton.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateButton(Self);
  Self.ConnectClick;
end;

{ TLabel }

constructor TLabel.Create;
begin
  Self.HandleNeeded;
end;

procedure TLabel.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateLabel(Self);
end;

{ TEdit }

constructor TEdit.Create;
begin
  Self.HandleNeeded;
end;

procedure TEdit.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateEdit(Self);
  Self.ConnectChange;
end;

procedure TEdit.ConnectChange;
begin
  WidgetSet.ConnectChange(Self);
end;

procedure TEdit.SetText(const s: string);
begin
  FText := s;
  if Self.Handle <> nil then
    WidgetSet.SetText(Self, FText);
end;

{ TCheckBox }

constructor TCheckBox.Create;
begin
  Self.HandleNeeded;
end;

procedure TCheckBox.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateCheckBox(Self);
  Self.ConnectChange;
end;

procedure TCheckBox.ConnectChange;
begin
  WidgetSet.ConnectChange(Self);
end;

procedure TCheckBox.SetChecked(v: Boolean);
begin
  if FChecked <> v then
  begin
    FChecked := v;
    if Self.Handle <> nil then
      WidgetSet.SetChecked(Self, FChecked);
  end;
end;

{ TMemo }

constructor TMemo.Create;
begin
  Self.HandleNeeded;
end;

procedure TMemo.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateMemo(Self);
  Self.ConnectChange;
end;

procedure TMemo.ConnectChange;
begin
  WidgetSet.ConnectChange(Self);
end;

function TMemo.GetText: string;
begin
  if Self.Handle <> nil then
    Result := WidgetSet.GetMemoText(Self)
  else
    Result := '';
end;

procedure TMemo.SetText(const s: string);
begin
  if Self.Handle <> nil then
    WidgetSet.SetMemoText(Self, s);
end;

{ TListBox }

constructor TListBox.Create;
begin
  FCount := 0;
  SetLength(FItems, 256);
  SetLength(FRows, 256);
  Self.HandleNeeded;
end;

procedure TListBox.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateListBox(Self);
  Self.ConnectChange;
end;

procedure TListBox.ConnectChange;
begin
  WidgetSet.ConnectChange(Self);
end;

procedure TListBox.AddItem(const s: string);
var row: Pointer;
begin
  if FCount < 256 then
  begin
    FItems[FCount] := s;
    if Self.Handle <> nil then
    begin
      row := WidgetSet.AddListItem(Self, s);
      FRows[FCount] := row;
    end;
    FCount := FCount + 1;
  end;
end;

procedure TListBox.Clear;
var i: Integer;
begin
  if Self.Handle <> nil then
  begin
    for i := 0 to FCount - 1 do
      if FRows[i] <> nil then
        WidgetSet.DestroyWidget(FRows[i]);
  end;
  for i := 0 to FCount - 1 do
    FItems[i] := '';
  FCount := 0;
end;

function TListBox.Item(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FItems[AIndex]
  else
    Result := '';
end;

function TListBox.GetItemIndex: Integer;
begin
  if Self.Handle <> nil then
    Result := WidgetSet.GetListIndex(Self)
  else
    Result := -1;
end;

procedure TListBox.SetItemIndex(v: Integer);
begin
  if Self.Handle <> nil then
    WidgetSet.SetListIndex(Self, v);
end;

{ TComboBox }

constructor TComboBox.Create;
begin
  FCount := 0;
  SetLength(FItems, 256);
  Self.HandleNeeded;
end;

procedure TComboBox.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateComboBox(Self);
  Self.ConnectChange;
end;

procedure TComboBox.ConnectChange;
begin
  WidgetSet.ConnectChange(Self);
end;

procedure TComboBox.AddItem(const s: string);
begin
  if FCount < 256 then
  begin
    FItems[FCount] := s;
    if Self.Handle <> nil then
      WidgetSet.AddComboItem(Self, s);
    FCount := FCount + 1;
  end;
end;

procedure TComboBox.Clear;
var i: Integer;
begin
  if Self.Handle <> nil then
    WidgetSet.ClearCombo(Self);
  for i := 0 to FCount - 1 do
    FItems[i] := '';
  FCount := 0;
end;

function TComboBox.Item(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FCount) then
    Result := FItems[AIndex]
  else
    Result := '';
end;

function TComboBox.GetItemIndex: Integer;
begin
  if Self.Handle <> nil then
    Result := WidgetSet.GetActiveIndex(Self)
  else
    Result := -1;
end;

procedure TComboBox.SetItemIndex(v: Integer);
begin
  if Self.Handle <> nil then
    WidgetSet.SetActiveIndex(Self, v);
end;

function TComboBox.GetText: string;
var idx: Integer;
begin
  idx := Self.GetItemIndex;
  if (idx >= 0) and (idx < FCount) then
    Result := FItems[idx]
  else
    Result := '';
end;

procedure TComboBox.SetText(const s: string);
var i, foundIdx: Integer;
begin
  foundIdx := -1;
  for i := 0 to FCount - 1 do
    if FItems[i] = s then
      foundIdx := i;
  if foundIdx >= 0 then
    Self.SetItemIndex(foundIdx);
end;

end.
