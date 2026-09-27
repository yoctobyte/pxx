{ SPDX-License-Identifier: Zlib }
unit comctrls;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ PCL-compatible ComCtrls -- for now, TTreeView and TTreeNode.

  A collapsible hierarchy, in the shape Delphi and Lazarus use: nodes carry
  Text and a caller payload, AddChild builds the tree, Expand/Collapse work
  per node, and Selected gives back the TTreeNode the user picked.

  WHAT THE WIDGETSET SEES AND WHAT IT DOES NOT. The seam takes and returns an
  OPAQUE STRING per node (uwidgetset's TreeAdd/TreeSelected) and knows nothing
  about TTreeNode -- the model lives here, entirely, and a second widgetset
  gets a tree by storing rows and minting keys. What it must NOT do is hand
  back an index: a tree has no single index, GTK's key is a path like '0:2:1',
  and a caller that never reads the string cannot come to depend on either.

  NO LAZY EXPANSION, DELIBERATELY, AND THAT IS A SCOPE LINE RATHER THAN AN
  OVERSIGHT. A lazy tree needs an expanding event, a placeholder child per
  unopened branch, and a way to drop a subtree again -- and every caller so
  far builds a bounded tree (espide caps at six levels below a project) that
  builds in a few ms. Declaring an OnExpanding nothing fires would be the
  exact trap this landing fixes in TListBox, whose published OnChange was
  dead. When a caller needs it, it arrives with the measurement that asked
  for it.

  NOT a TComponent-owned hierarchy: TTreeNode is a plain object owned by its
  TTreeView, freed by Clear and by the view's destructor. Streaming a tree
  from an .lfm is not a thing anyone has needed. }

interface

uses classes_lite, controls, uwidgetset;

type
  TTreeView = class;

  TTreeNode = class
  private
    FTree: TTreeView;
    FParent: TTreeNode;
    FKey: AnsiString;        { the widgetset's opaque handle for this row }
    FText: AnsiString;
    FData: AnsiString;       { the caller's payload -- a path, in an IDE }
    FTag: Integer;
    FChildren: array of TTreeNode;
    FCount: Integer;
    procedure SetText(const v: AnsiString);
  public
    constructor Create(ATree: TTreeView; AParent: TTreeNode; const AKey: AnsiString);
    destructor Destroy; override;
    function AddChild(const AText, AData: AnsiString): TTreeNode;
    function Item(AIndex: Integer): TTreeNode;
    { ADeep also opens every descendant }
    procedure Expand(ADeep: Boolean);
    procedure Collapse;
    procedure Select;
    property Count: Integer read FCount;
    property Parent: TTreeNode read FParent;
    property Tree: TTreeView read FTree;
    property Key: AnsiString read FKey;
    property Text: AnsiString read FText write SetText;
    property Data: AnsiString read FData write FData;
    property Tag: Integer read FTag write FTag;
  end;

  TTreeView = class(TWinControl)
  private
    FRoots: array of TTreeNode;
    FRootCount: Integer;
    FOnChange: TMethod;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure CreateHandle; override;
    function AddRoot(const AText, AData: AnsiString): TTreeNode;
    procedure Clear;
    { The node whose row is selected, or nil. }
    function Selected: TTreeNode;
    { The node the widgetset's key belongs to, or nil. }
    function NodeOf(const AKey: AnsiString): TTreeNode;
    function Root(AIndex: Integer): TTreeNode;
    procedure ExpandAll;
    procedure CollapseAll;
    property RootCount: Integer read FRootCount;
  published
    { fires when the selected row changes; Sender is the TTreeView, and the
      handler reads Selected }
    property OnChange: TMethod read FOnChange write FOnChange;
  end;

implementation

{ ---- TTreeNode ---- }

constructor TTreeNode.Create(ATree: TTreeView; AParent: TTreeNode; const AKey: AnsiString);
begin
  FTree := ATree;
  FParent := AParent;
  FKey := AKey;
  FText := '';
  FData := '';
  FTag := 0;
  FCount := 0;
  SetLength(FChildren, 8);
end;

destructor TTreeNode.Destroy;
var i: Integer;
begin
  for i := 0 to FCount - 1 do
    FChildren[i].Free;
  FCount := 0;
  inherited Destroy;
end;

procedure TTreeNode.SetText(const v: AnsiString);
begin
  FText := v;
  if (FTree <> nil) and (FTree.Handle <> nil) then
    WidgetSet.TreeSetText(FTree, FKey, v);
end;

function TTreeNode.AddChild(const AText, AData: AnsiString): TTreeNode;
var key: AnsiString; n: TTreeNode;
begin
  key := WidgetSet.TreeAdd(FTree, FKey, AText);
  n := TTreeNode.Create(FTree, Self, key);
  n.FText := AText;
  n.FData := AData;
  if FCount >= Length(FChildren) then SetLength(FChildren, FCount + 16);
  FChildren[FCount] := n;
  FCount := FCount + 1;
  AddChild := n;
end;

function TTreeNode.Item(AIndex: Integer): TTreeNode;
begin
  if (AIndex < 0) or (AIndex >= FCount) then Item := nil
  else Item := FChildren[AIndex];
end;

procedure TTreeNode.Expand(ADeep: Boolean);
begin
  WidgetSet.TreeExpand(FTree, FKey, ADeep);
end;

procedure TTreeNode.Collapse;
begin
  WidgetSet.TreeCollapse(FTree, FKey);
end;

procedure TTreeNode.Select;
begin
  WidgetSet.TreeSelect(FTree, FKey);
end;

{ ---- TTreeView ---- }

constructor TTreeView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FRootCount := 0;
  SetLength(FRoots, 16);
  Self.HandleNeeded;
end;

destructor TTreeView.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TTreeView.CreateHandle;
begin
  Self.Handle := WidgetSet.CreateTreeView(Self);
end;

function TTreeView.AddRoot(const AText, AData: AnsiString): TTreeNode;
var key: AnsiString; n: TTreeNode;
begin
  key := WidgetSet.TreeAdd(Self, '', AText);
  n := TTreeNode.Create(Self, nil, key);
  n.FText := AText;
  n.FData := AData;
  if FRootCount >= Length(FRoots) then SetLength(FRoots, FRootCount + 16);
  FRoots[FRootCount] := n;
  FRootCount := FRootCount + 1;
  AddRoot := n;
end;

procedure TTreeView.Clear;
var i: Integer;
begin
  for i := 0 to FRootCount - 1 do
    FRoots[i].Free;
  FRootCount := 0;
  WidgetSet.TreeClear(Self);
end;

function TTreeView.Root(AIndex: Integer): TTreeNode;
begin
  if (AIndex < 0) or (AIndex >= FRootCount) then Root := nil
  else Root := FRoots[AIndex];
end;

{ Depth-first, comparing keys. Linear in the tree, which is what a selection
  change can afford; the alternative is a map keyed by a string the widgetset
  mints, and a tree small enough to display is small enough to walk. }
function NodeIn(n: TTreeNode; const AKey: AnsiString): TTreeNode;
var i: Integer; r: TTreeNode;
begin
  if n.Key = AKey then begin NodeIn := n; Exit; end;
  for i := 0 to n.Count - 1 do
  begin
    r := NodeIn(n.Item(i), AKey);
    if r <> nil then begin NodeIn := r; Exit; end;
  end;
  NodeIn := nil;
end;

function TTreeView.NodeOf(const AKey: AnsiString): TTreeNode;
var i: Integer; r: TTreeNode;
begin
  NodeOf := nil;
  if AKey = '' then Exit;
  for i := 0 to FRootCount - 1 do
  begin
    r := NodeIn(FRoots[i], AKey);
    if r <> nil then begin NodeOf := r; Exit; end;
  end;
end;

function TTreeView.Selected: TTreeNode;
begin
  Selected := NodeOf(WidgetSet.TreeSelected(Self));
end;

procedure TTreeView.ExpandAll;
begin
  WidgetSet.TreeExpand(Self, '', True);
end;

procedure TTreeView.CollapseAll;
begin
  WidgetSet.TreeCollapse(Self, '');
end;

end.
