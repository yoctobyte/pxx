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

implementation

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

end.
