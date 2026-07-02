{ SPDX-License-Identifier: Zlib }
unit menus;

interface

uses classes_lite, typinfo;

type
  TMenuItem = class(TComponent)
  private
    FCaption: string;
    FOnClick: TMethod;
    FEnabled: Boolean;
    FVisible: Boolean;
    FHandle: Pointer;
    FMenuOwner: TComponent;
    procedure SetCaption(const s: string);
    procedure SetEnabled(v: Boolean);
    procedure SetVisible(v: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy;
    procedure Add(Item: TMenuItem);
    procedure Click;
    function GetItem(Index: Integer): TMenuItem;
    function Item(Index: Integer): TMenuItem;
    function GetCount: Integer;
    property Handle: Pointer read FHandle write FHandle;
    property Count: Integer read GetCount;
  published
    property Caption: string read FCaption write SetCaption;
    property Enabled: Boolean read FEnabled write SetEnabled;
    property Visible: Boolean read FVisible write SetVisible;
    property OnClick: TMethod read FOnClick write FOnClick;
  end;

  TMenu = class(TComponent)
  private
    FRootMenuItem: TMenuItem;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy;
    property Items: TMenuItem read FRootMenuItem;
  end;

  TMainMenu = class(TMenu)
  end;

implementation

{ TMenuItem }

constructor TMenuItem.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := True;
  FVisible := True;
  FMenuOwner := nil;
end;

destructor TMenuItem.Destroy;
begin
end;

procedure TMenuItem.SetCaption(const s: string);
begin
  FCaption := s;
end;

procedure TMenuItem.SetEnabled(v: Boolean);
begin
  FEnabled := v;
end;

procedure TMenuItem.SetVisible(v: Boolean);
begin
  FVisible := v;
end;

function TMenuItem.GetCount: Integer;
begin
  if FMenuOwner <> nil then
    Result := FMenuOwner.ChildCount
  else
    Result := Self.ChildCount;
end;

function TMenuItem.GetItem(Index: Integer): TMenuItem;
var
  p: Pointer;
begin
  if FMenuOwner <> nil then
    p := FMenuOwner.Child(Index)
  else
    p := Self.Child(Index);
  Result := TMenuItem(p);
end;

function TMenuItem.Item(Index: Integer): TMenuItem;
begin
  Result := GetItem(Index);
end;

procedure TMenuItem.Add(Item: TMenuItem);
begin
  if FMenuOwner <> nil then
    FMenuOwner.AddChild(Item)
  else
    Self.AddChild(Item);
end;

procedure TMenuItem.Click;
begin
end;

{ TMenu }

constructor TMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRootMenuItem := TMenuItem.Create(nil);
  FRootMenuItem.FMenuOwner := Self;
end;

destructor TMenu.Destroy;
begin
  FRootMenuItem.Destroy;
end;

end.
