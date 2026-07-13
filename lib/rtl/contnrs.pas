{ SPDX-License-Identifier: Zlib }
unit contnrs;
{ FPC's `contnrs` containers, as much of the surface as real code actually uses.

  Built on classes.TFPList (a plain pointer list), which is where the storage and the
  bounds discipline already live. TFPObjectList adds ownership; TFPHashObjectList adds a
  name per slot.

  On the "Hash" in TFPHashObjectList: FPC's is a real hash table. This one keeps the names
  in a parallel array and searches them linearly. That is a PERFORMANCE difference, not a
  behavioural one -- the ordering, the duplicate rules and the return values are the same,
  and every operation gives the answer FPC's does. It is called out here rather than left
  for someone to discover: if a caller ever needs the O(1), this is where to put it, and
  nothing above it has to change.

  fcl-json's fpjson.pp uses both (a JSON array is a TFPObjectList, a JSON object is a
  TFPHashObjectList). }

interface

uses classes;

type
  { FPC's list comparison callback: <0, 0, >0. Declared here because classes.TList does
    not carry a Sort yet. }
  TListSortCompare = function(Item1, Item2: Pointer): Integer;

  { ---- TFPObjectList: an object list that can own what it holds ---- }
  TFPObjectList = class(TObject)
  private
    FList: TFPList;
    FFreeObjects: Boolean;
    function GetItem(Index: Integer): TObject;
    procedure SetItem(Index: Integer; AObject: TObject);
    function GetCount: Integer;
  public
    constructor Create; overload;
    constructor Create(FreeObjects: Boolean); overload;
    destructor Destroy; override;

    function Add(AObject: TObject): Integer;
    procedure Clear;
    procedure Delete(Index: Integer);
    procedure Exchange(Index1, Index2: Integer);
    { Extract removes WITHOUT freeing, whatever OwnsObjects says -- that is the whole
      point of it, and the difference from Remove. }
    function Extract(Item: TObject): TObject;
    function Remove(AObject: TObject): Integer;
    function IndexOf(AObject: TObject): Integer;
    procedure Insert(Index: Integer; AObject: TObject);
    { Move an item to another index, shifting the rest -- NOT a swap (that is Exchange). }
    procedure Move(CurIndex, NewIndex: Integer);
    { Stable insertion sort by the callback. FPC takes a comparison function; the same
      contract: <0, 0, >0. }
    procedure Sort(Compare: TListSortCompare);

    property Count: Integer read GetCount;
    property OwnsObjects: Boolean read FFreeObjects write FFreeObjects;
    property Items[Index: Integer]: TObject read GetItem write SetItem; default;
  end;

  { ---- TFPHashObjectList: an ordered object list with a NAME per slot ---- }
  TFPHashObjectList = class(TObject)
  private
    FList: TFPObjectList;
    FNames: array of string;
    function GetItem(Index: Integer): TObject;
    procedure SetItem(Index: Integer; AObject: TObject);
    function GetCount: Integer;
    function GetOwnsObjects: Boolean;
    procedure SetOwnsObjects(V: Boolean);
  public
    constructor Create; overload;
    constructor Create(FreeObjects: Boolean); overload;
    destructor Destroy; override;

    function Add(const AName: string; AObject: TObject): Integer;
    procedure Clear;
    procedure Delete(Index: Integer);
    function Extract(Item: TObject): TObject;
    function Remove(AObject: TObject): Integer;
    function IndexOf(AObject: TObject): Integer;

    { Find by NAME: the object, or nil. FindIndexOf gives its index, or -1. }
    function Find(const AName: string): TObject;
    function FindIndexOf(const AName: string): Integer;
    { The name stored at Index ('' when out of range). }
    function NameOfIndex(Index: Integer): string;

    property Count: Integer read GetCount;
    property OwnsObjects: Boolean read GetOwnsObjects write SetOwnsObjects;
    property Items[Index: Integer]: TObject read GetItem write SetItem; default;
  end;

implementation

{ ===== TFPObjectList ===== }

constructor TFPObjectList.Create;
begin
  FList := TFPList.Create;
  FFreeObjects := True;
end;

constructor TFPObjectList.Create(FreeObjects: Boolean);
begin
  FList := TFPList.Create;
  FFreeObjects := FreeObjects;
end;

destructor TFPObjectList.Destroy;
begin
  Clear;
  FList.Free;
  inherited Destroy;
end;

function TFPObjectList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TFPObjectList.GetItem(Index: Integer): TObject;
begin
  Result := TObject(FList[Index]);
end;

procedure TFPObjectList.SetItem(Index: Integer; AObject: TObject);
var old: TObject;
begin
  old := TObject(FList[Index]);
  if FFreeObjects and (old <> nil) and (old <> AObject) then
    old.Free;
  FList[Index] := Pointer(AObject);
end;

function TFPObjectList.Add(AObject: TObject): Integer;
begin
  Result := FList.Add(Pointer(AObject));
end;

procedure TFPObjectList.Clear;
var i: Integer;
begin
  if FFreeObjects then
    for i := 0 to FList.Count - 1 do
      if FList[i] <> nil then
        TObject(FList[i]).Free;
  FList.Clear;
end;

procedure TFPObjectList.Delete(Index: Integer);
begin
  if FFreeObjects and (FList[Index] <> nil) then
    TObject(FList[Index]).Free;
  FList.Delete(Index);
end;

procedure TFPObjectList.Exchange(Index1, Index2: Integer);
var tmp: Pointer;
begin
  tmp := FList[Index1];
  FList[Index1] := FList[Index2];
  FList[Index2] := tmp;
end;

function TFPObjectList.Extract(Item: TObject): TObject;
var i: Integer;
begin
  Result := nil;
  i := IndexOf(Item);
  if i >= 0 then
  begin
    Result := Item;
    FList.Delete(i);          { NOT Delete(i) -- Extract never frees }
  end;
end;

function TFPObjectList.Remove(AObject: TObject): Integer;
begin
  Result := IndexOf(AObject);
  if Result >= 0 then
    Delete(Result);           { frees, if we own it }
end;

function TFPObjectList.IndexOf(AObject: TObject): Integer;
begin
  Result := FList.IndexOf(Pointer(AObject));
end;

procedure TFPObjectList.Insert(Index: Integer; AObject: TObject);
begin
  FList.Insert(Index, Pointer(AObject));
end;

procedure TFPObjectList.Move(CurIndex, NewIndex: Integer);
var p: Pointer;
begin
  if CurIndex = NewIndex then Exit;
  p := FList[CurIndex];
  FList.Delete(CurIndex);
  FList.Insert(NewIndex, p);
end;

procedure TFPObjectList.Sort(Compare: TListSortCompare);
var i, j: Integer; cur: Pointer;
begin
  { insertion sort -- stable, and the lists here are small }
  for i := 1 to FList.Count - 1 do
  begin
    cur := FList[i];
    j := i - 1;
    while (j >= 0) and (Compare(FList[j], cur) > 0) do
    begin
      FList[j + 1] := FList[j];
      Dec(j);
    end;
    FList[j + 1] := cur;
  end;
end;

{ ===== TFPHashObjectList ===== }

constructor TFPHashObjectList.Create;
begin
  FList := TFPObjectList.Create(True);
  SetLength(FNames, 0);
end;

constructor TFPHashObjectList.Create(FreeObjects: Boolean);
begin
  FList := TFPObjectList.Create(FreeObjects);
  SetLength(FNames, 0);
end;

destructor TFPHashObjectList.Destroy;
begin
  FList.Free;
  inherited Destroy;
end;

function TFPHashObjectList.GetOwnsObjects: Boolean;
begin
  Result := FList.OwnsObjects;
end;

procedure TFPHashObjectList.SetOwnsObjects(V: Boolean);
begin
  FList.OwnsObjects := V;
end;

function TFPHashObjectList.GetCount: Integer;
begin
  Result := FList.Count;
end;

function TFPHashObjectList.GetItem(Index: Integer): TObject;
begin
  Result := FList[Index];
end;

procedure TFPHashObjectList.SetItem(Index: Integer; AObject: TObject);
begin
  FList[Index] := AObject;
end;

function TFPHashObjectList.Add(const AName: string; AObject: TObject): Integer;
begin
  Result := FList.Add(AObject);
  SetLength(FNames, FList.Count);
  FNames[Result] := AName;
end;

procedure TFPHashObjectList.Clear;
begin
  FList.Clear;
  SetLength(FNames, 0);
end;

procedure TFPHashObjectList.Delete(Index: Integer);
var i: Integer;
begin
  FList.Delete(Index);
  for i := Index to Length(FNames) - 2 do
    FNames[i] := FNames[i + 1];
  SetLength(FNames, FList.Count);
end;

function TFPHashObjectList.Extract(Item: TObject): TObject;
var i: Integer;
begin
  Result := nil;
  i := IndexOf(Item);
  if i >= 0 then
  begin
    Result := FList.Extract(Item);   { never frees }
    for i := i to Length(FNames) - 2 do
      FNames[i] := FNames[i + 1];
    SetLength(FNames, FList.Count);
  end;
end;

function TFPHashObjectList.Remove(AObject: TObject): Integer;
begin
  Result := IndexOf(AObject);
  if Result >= 0 then
    Delete(Result);
end;

function TFPHashObjectList.IndexOf(AObject: TObject): Integer;
begin
  Result := FList.IndexOf(AObject);
end;

function TFPHashObjectList.FindIndexOf(const AName: string): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to FList.Count - 1 do
    if FNames[i] = AName then
    begin
      Result := i;
      Exit;
    end;
end;

function TFPHashObjectList.Find(const AName: string): TObject;
var i: Integer;
begin
  Result := nil;
  i := FindIndexOf(AName);
  if i >= 0 then
    Result := FList[i];
end;

function TFPHashObjectList.NameOfIndex(Index: Integer): string;
begin
  if (Index >= 0) and (Index < Length(FNames)) then
    Result := FNames[Index]
  else
    Result := '';
end;

end.
