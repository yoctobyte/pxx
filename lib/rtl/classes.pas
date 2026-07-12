{ SPDX-License-Identifier: Zlib }
unit classes;
{ Classic FPC-compatible Classes — the traditional, non-generic surface every
  FPC/Delphi program (and Synapse) expects: TList (a list of Pointer),
  TStrings (abstract) + TStringList (concrete). Standard inheritance on purpose
  (TStringList descends from TStrings); a type-safe TList<T> lives separately in
  a future Generics.Collections, not here. The streaming runtime (TComponent,
  TReader) is in classes_lite.

  Surface: TList, TStrings, TStringList, TStream + TMemoryStream — all working and
  smoked (the Read/Write-method-name and untyped-method-param gaps that blocked
  the stream surface were fixed Track A, v54). TStringList.Sort uses CompareStr.

  STATUS: TList, TStrings and TStringList all work and are smoked, Sort included.
  Sort compares via sysutils.CompareStr (char-code based) — which is what FPC's
  TStringList.Sort uses anyway, and it correctly sidesteps the broken AnsiString
  `<`/`>` operators (bug-string-ordering-comparison-constant, Track A — still open
  for user code that uses those operators directly). }

interface

uses sysutils;   { CompareStr for Sort }

type
  { ---- TPersistent: assignable base (FPC Classes surface) ---- }
  TPersistent = class(TObject)
  protected
    procedure AssignTo(Dest: TPersistent); virtual;
  public
    procedure Assign(Source: TPersistent); virtual;
    function GetNamePath: string; virtual;
  end;

  { ---- TComponent: owner/child component model (FPC Classes surface) ----
    A component owns the components created with it as AOwner; freeing the owner
    frees them. This is the base FCL/LCL units build on. Streaming (TReader) is
    the separate classes_lite.TComponent for pxx's own PCL widget stack; this is
    the FPC-facing `uses Classes` surface. }
  TOperation = (opInsert, opRemove);

  TComponent = class;
  TComponentClass = class of TComponent;

  TComponent = class(TPersistent)
  private
    FOwner: TComponent;
    FComponents: array of TComponent;
    FComponentCount: Integer;
    FName: string;
    FTag: NativeInt;
    function GetComponent(Index: Integer): TComponent;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); virtual;
  public
    constructor Create(AOwner: TComponent); virtual;
    destructor Destroy; override;
    procedure InsertComponent(AComponent: TComponent);
    procedure RemoveComponent(AComponent: TComponent);
    function FindComponent(const AName: string): TComponent;
    property Owner: TComponent read FOwner;
    property Components[Index: Integer]: TComponent read GetComponent;
    property ComponentCount: Integer read FComponentCount;
    property Name: string read FName write FName;
    property Tag: NativeInt read FTag write FTag;
  end;

  { ---- TStream: abstract byte stream + TMemoryStream concrete ---- }
  TSeekOrigin = (soBeginning, soCurrent, soEnd);

  TStream = class
  protected
    function GetSize: Int64; virtual;
    function GetPosition: Int64; virtual;
    procedure SetPosition(const Pos: Int64); virtual;
    procedure SetSize64(const NewSize: Int64); virtual;
  public
    function Read(var Buffer; Count: Longint): Longint; virtual; abstract;
    function Write(const Buffer; Count: Longint): Longint; virtual; abstract;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; virtual; abstract;
    procedure ReadBuffer(var Buffer; Count: Longint);
    procedure WriteBuffer(const Buffer; Count: Longint);
    function CopyFrom(Source: TStream; Count: Int64): Int64;
    property Position: Int64 read GetPosition write SetPosition;
    property Size: Int64 read GetSize write SetSize64;
  end;

  TMemoryStream = class(TStream)
  private
    FData: array of Byte;
    FSize: Int64;
    FPosition: Int64;
    procedure EnsureCapacity(needed: Int64);
  protected
    function GetSize: Int64; override;
    procedure SetSize64(const NewSize: Int64); override;
  public
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    procedure Clear;
    procedure SetSize(NewSize: Int64);
    function Memory: Pointer;
  end;

  { FPC TList mutation-notification hook. A descendant (e.g. TObjectList)
    overrides Notify to react to element add/remove — the mechanism that lets
    an owning list free its objects on Delete/Clear. Base Notify does nothing. }
  TListNotification = (lnAdded, lnExtracted, lnDeleted);

  { ---- TList: a growable list of untyped pointers ---- }
  TList = class
  private
    FItems: array of Pointer;
    FCount: Integer;
    function GetItem(Index: Integer): Pointer;
    procedure SetItem(Index: Integer; Item: Pointer);
  protected
    procedure Notify(Ptr: Pointer; Action: TListNotification); virtual;
  public
    function Add(Item: Pointer): Integer;
    procedure Clear;
    procedure Delete(Index: Integer);
    procedure Insert(Index: Integer; Item: Pointer);
    function IndexOf(Item: Pointer): Integer;
    function Remove(Item: Pointer): Integer;
    property Count: Integer read FCount;
    property Items[Index: Integer]: Pointer read GetItem write SetItem; default;
  end;

  { ---- TStrings: abstract string-list base ---- }
  TStrings = class
  protected
    function Get(Index: Integer): string; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetObject(Index: Integer): TObject; virtual; abstract;
    procedure Put(Index: Integer; const S: string); virtual; abstract;
    procedure PutObject(Index: Integer; AObject: TObject); virtual; abstract;
  public
    function Add(const S: string): Integer; virtual;
    function AddObject(const S: string; AObject: TObject): Integer; virtual;
    procedure Clear; virtual; abstract;
    procedure Delete(Index: Integer); virtual; abstract;
    procedure Insert(Index: Integer; const S: string); virtual; abstract;
    function IndexOf(const S: string): Integer; virtual;
    function GetText: string;
    procedure SetText(const Value: string);
    procedure LoadFromStream(Stream: TStream);
    procedure SaveToStream(Stream: TStream);
    procedure Assign(Source: TStrings); virtual;
    procedure AddStrings(Source: TStrings);
    property Count: Integer read GetCount;
    property Strings[Index: Integer]: string read Get write Put; default;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Text: string read GetText write SetText;
  end;

  { ---- TStringList: concrete string list with paired objects ---- }
  TStringItem = record
    FStr: string;
    FObj: TObject;
  end;

  TStringList = class(TStrings)
  private
    FList: array of TStringItem;
    FCount: Integer;
  protected
    function Get(Index: Integer): string; override;
    function GetCount: Integer; override;
    function GetObject(Index: Integer): TObject; override;
    procedure Put(Index: Integer; const S: string); override;
    procedure PutObject(Index: Integer; AObject: TObject); override;
  public
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Insert(Index: Integer; const S: string); override;
    procedure Sort;
  end;

implementation

{ ============================ TStream ============================ }

function TStream.GetPosition: Int64;
begin
  Result := Seek(0, soCurrent);
end;

procedure TStream.SetPosition(const Pos: Int64);
begin
  Seek(Pos, soBeginning);
end;

procedure TStream.SetSize64(const NewSize: Int64);
begin
  { base: not resizable (FPC's default raises; keep it a no-op error-free stub) }
end;

procedure TMemoryStream.SetSize64(const NewSize: Int64);
begin
  SetSize(NewSize);
end;

function TStream.GetSize: Int64;
var p: Int64;
begin
  p := Seek(0, soCurrent);
  Result := Seek(0, soEnd);
  Seek(p, soBeginning);
end;

procedure TStream.ReadBuffer(var Buffer; Count: Longint);
begin
  Read(Buffer, Count);
end;

procedure TStream.WriteBuffer(const Buffer; Count: Longint);
begin
  Write(Buffer, Count);
end;

function TStream.CopyFrom(Source: TStream; Count: Int64): Int64;
var buf: array[0..4095] of Byte; chunk, got: Longint;
begin
  Result := 0;
  while Count > 0 do
  begin
    if Count > 4096 then chunk := 4096 else chunk := Longint(Count);
    got := Source.Read(buf[0], chunk);
    if got <= 0 then Break;
    Write(buf[0], got);
    Result := Result + got;
    Count := Count - got;
  end;
end;

{ ============================ TMemoryStream ============================ }

procedure TMemoryStream.EnsureCapacity(needed: Int64);
var cap: Int64;
begin
  cap := Length(FData);
  if needed <= cap then Exit;
  if cap = 0 then cap := 64;
  while cap < needed do cap := cap * 2;
  SetLength(FData, cap);
end;

function TMemoryStream.GetSize: Int64;
begin
  Result := FSize;
end;

function TMemoryStream.Read(var Buffer; Count: Longint): Longint;
var avail: Int64;
begin
  avail := FSize - FPosition;
  if avail <= 0 then begin Result := 0; Exit; end;
  if Count > avail then Count := Longint(avail);
  if Count > 0 then Move(FData[FPosition], Buffer, Count);
  FPosition := FPosition + Count;
  Result := Count;
end;

function TMemoryStream.Write(const Buffer; Count: Longint): Longint;
begin
  if Count <= 0 then begin Result := 0; Exit; end;
  EnsureCapacity(FPosition + Count);
  Move(Buffer, FData[FPosition], Count);
  FPosition := FPosition + Count;
  if FPosition > FSize then FSize := FPosition;
  Result := Count;
end;

function TMemoryStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
begin
  case Origin of
    soBeginning: FPosition := Offset;
    soCurrent:   FPosition := FPosition + Offset;
    soEnd:       FPosition := FSize + Offset;
  end;
  if FPosition < 0 then FPosition := 0;
  Result := FPosition;
end;

procedure TMemoryStream.Clear;
begin
  SetLength(FData, 0);
  FSize := 0;
  FPosition := 0;
end;

procedure TMemoryStream.SetSize(NewSize: Int64);
begin
  EnsureCapacity(NewSize);
  FSize := NewSize;
  if FPosition > FSize then FPosition := FSize;
end;

function TMemoryStream.Memory: Pointer;
begin
  if Length(FData) > 0 then Result := @FData[0] else Result := nil;
end;

{ ============================ TList ============================ }

function TList.GetItem(Index: Integer): Pointer;
begin
  if (Index >= 0) and (Index < FCount) then Result := FItems[Index]
  else Result := nil;
end;

procedure TList.SetItem(Index: Integer; Item: Pointer);
begin
  if (Index >= 0) and (Index < FCount) then FItems[Index] := Item;
end;

procedure TList.Notify(Ptr: Pointer; Action: TListNotification);
begin
  { base: no-op; descendants (e.g. an owning list) override to free/track }
end;

function TList.Add(Item: Pointer): Integer;
begin
  if FCount >= Length(FItems) then
  begin
    if Length(FItems) = 0 then SetLength(FItems, 8)
    else SetLength(FItems, Length(FItems) * 2);
  end;
  FItems[FCount] := Item;
  Result := FCount;
  FCount := FCount + 1;
  Notify(Item, lnAdded);
end;

procedure TList.Clear;
var i: Integer;
begin
  for i := 0 to FCount - 1 do Notify(FItems[i], lnDeleted);
  SetLength(FItems, 0);
  FCount := 0;
end;

procedure TList.Delete(Index: Integer);
var i: Integer;
begin
  if (Index < 0) or (Index >= FCount) then Exit;
  Notify(FItems[Index], lnDeleted);
  for i := Index to FCount - 2 do FItems[i] := FItems[i + 1];
  FCount := FCount - 1;
end;

procedure TList.Insert(Index: Integer; Item: Pointer);
var i: Integer;
begin
  if (Index < 0) or (Index > FCount) then Exit;
  { grow by one WITHOUT going through Add (which would fire Notify(nil, lnAdded)) }
  if FCount >= Length(FItems) then
  begin
    if Length(FItems) = 0 then SetLength(FItems, 8)
    else SetLength(FItems, Length(FItems) * 2);
  end;
  FCount := FCount + 1;
  for i := FCount - 1 downto Index + 1 do FItems[i] := FItems[i - 1];
  FItems[Index] := Item;
  Notify(Item, lnAdded);
end;

function TList.IndexOf(Item: Pointer): Integer;
var i: Integer;
begin
  for i := 0 to FCount - 1 do
    if FItems[i] = Item then begin Result := i; Exit; end;
  Result := -1;
end;

function TList.Remove(Item: Pointer): Integer;
begin
  Result := IndexOf(Item);
  if Result >= 0 then Self.Delete(Result);   { Self. — Delete is also a builtin }
end;

{ ============================ TPersistent ============================ }

procedure TPersistent.AssignTo(Dest: TPersistent);
begin
  { base: nothing — a subclass overrides Assign or AssignTo }
end;

procedure TPersistent.Assign(Source: TPersistent);
begin
  if Source <> nil then Source.AssignTo(Self);
end;

function TPersistent.GetNamePath: string;
begin
  Result := '';
end;

{ ============================ TComponent ============================ }

constructor TComponent.Create(AOwner: TComponent);
begin
  FOwner := nil;
  FComponentCount := 0;
  FName := '';
  FTag := 0;
  if AOwner <> nil then AOwner.InsertComponent(Self);
end;

destructor TComponent.Destroy;
var c: TComponent;
begin
  { free the components we own; each child's Destroy calls Owner.RemoveComponent,
    draining FComponents from the tail. (Temp `c` because `arr[i].Free` does not
    parse — a known pxx gap.) }
  while FComponentCount > 0 do
  begin
    c := FComponents[FComponentCount - 1];
    c.Free;
  end;
  if FOwner <> nil then FOwner.RemoveComponent(Self);
  inherited Destroy;
end;

function TComponent.GetComponent(Index: Integer): TComponent;
begin
  if (Index < 0) or (Index >= FComponentCount) then
    Result := nil
  else
    Result := FComponents[Index];
end;

procedure TComponent.Notification(AComponent: TComponent; Operation: TOperation);
begin
  { base: no-op; a subclass reacts to owned-component insert/remove }
end;

procedure TComponent.InsertComponent(AComponent: TComponent);
begin
  if AComponent = nil then Exit;
  AComponent.FOwner := Self;
  if FComponentCount >= Length(FComponents) then
  begin
    if Length(FComponents) = 0 then SetLength(FComponents, 8)
    else SetLength(FComponents, Length(FComponents) * 2);
  end;
  FComponents[FComponentCount] := AComponent;
  FComponentCount := FComponentCount + 1;
  Notification(AComponent, opInsert);
end;

procedure TComponent.RemoveComponent(AComponent: TComponent);
var i, j: Integer;
begin
  for i := 0 to FComponentCount - 1 do
    if FComponents[i] = AComponent then
    begin
      Notification(AComponent, opRemove);
      for j := i to FComponentCount - 2 do FComponents[j] := FComponents[j + 1];
      FComponentCount := FComponentCount - 1;
      AComponent.FOwner := nil;
      Exit;
    end;
end;

function TComponent.FindComponent(const AName: string): TComponent;
var i: Integer;
begin
  Result := nil;
  if AName = '' then Exit;
  for i := 0 to FComponentCount - 1 do
    if SameText(FComponents[i].FName, AName) then
    begin
      Result := FComponents[i];
      Exit;
    end;
end;

{ ============================ TStrings ============================ }

function TStrings.Add(const S: string): Integer;
begin
  Result := GetCount;
  Self.Insert(Result, S);                    { Self. — Insert is also a builtin }
end;

function TStrings.AddObject(const S: string; AObject: TObject): Integer;
begin
  Result := Add(S);
  PutObject(Result, AObject);
end;

function TStrings.IndexOf(const S: string): Integer;
var i: Integer;
begin
  for i := 0 to GetCount - 1 do
    if Get(i) = S then begin Result := i; Exit; end;
  Result := -1;
end;

function TStrings.GetText: string;
var i: Integer; r: string;
begin
  r := '';
  for i := 0 to GetCount - 1 do r := r + Get(i) + #13#10;
  Result := r;
end;

procedure TStrings.SetText(const Value: string);
var i, n: Integer; line: string; c: Char;
begin
  Clear;
  line := '';
  n := Length(Value);
  for i := 1 to n do
  begin
    c := Value[i];
    if c = #10 then
    begin
      if (Length(line) > 0) and (line[Length(line)] = #13) then
        line := Copy(line, 1, Length(line) - 1);
      Add(line);
      line := '';
    end
    else
      line := line + c;
  end;
  if line <> '' then Add(line);
end;

procedure TStrings.Assign(Source: TStrings);
var i: Integer;
begin
  Clear;
  if Source = nil then Exit;
  for i := 0 to Source.Count - 1 do
    AddObject(Source.Strings[i], Source.Objects[i]);
end;

procedure TStrings.AddStrings(Source: TStrings);
var i: Integer;
begin
  if Source = nil then Exit;
  for i := 0 to Source.Count - 1 do
    AddObject(Source.Strings[i], Source.Objects[i]);
end;

procedure TStrings.LoadFromStream(Stream: TStream);
var
  buf: AnsiString;
  n: Integer;
begin
  { read the stream's remaining bytes from Position and parse as lines }
  n := Stream.Size - Stream.Position;
  if n < 0 then n := 0;
  SetLength(buf, n);
  if n > 0 then
    Stream.Read(PChar(buf)^, n);
  SetText(buf);
end;

procedure TStrings.SaveToStream(Stream: TStream);
var
  buf: AnsiString;
begin
  buf := GetText;
  if Length(buf) > 0 then
    Stream.Write(PChar(buf)^, Length(buf));
end;

{ ============================ TStringList ============================ }

function TStringList.GetCount: Integer;
begin
  Result := FCount;
end;

function TStringList.Get(Index: Integer): string;
begin
  if (Index >= 0) and (Index < FCount) then Result := FList[Index].FStr
  else Result := '';
end;

function TStringList.GetObject(Index: Integer): TObject;
begin
  if (Index >= 0) and (Index < FCount) then Result := FList[Index].FObj
  else Result := nil;
end;

procedure TStringList.Put(Index: Integer; const S: string);
begin
  if (Index >= 0) and (Index < FCount) then FList[Index].FStr := S;
end;

procedure TStringList.PutObject(Index: Integer; AObject: TObject);
begin
  if (Index >= 0) and (Index < FCount) then FList[Index].FObj := AObject;
end;

procedure TStringList.Clear;
begin
  SetLength(FList, 0);
  FCount := 0;
end;

procedure TStringList.Delete(Index: Integer);
var i: Integer;
begin
  if (Index < 0) or (Index >= FCount) then Exit;
  for i := Index to FCount - 2 do FList[i] := FList[i + 1];
  FCount := FCount - 1;
end;

procedure TStringList.Insert(Index: Integer; const S: string);
var i: Integer;
begin
  if (Index < 0) or (Index > FCount) then Exit;
  if FCount >= Length(FList) then
  begin
    if Length(FList) = 0 then SetLength(FList, 8)
    else SetLength(FList, Length(FList) * 2);
  end;
  for i := FCount downto Index + 1 do FList[i] := FList[i - 1];
  FList[Index].FStr := S;
  FList[Index].FObj := nil;
  FCount := FCount + 1;
end;

procedure TStringList.Sort;
var i, j: Integer; tmp: TStringItem;
begin
  { insertion sort by string value }
  for i := 1 to FCount - 1 do
  begin
    tmp := FList[i];
    j := i - 1;
    while (j >= 0) and (CompareStr(FList[j].FStr, tmp.FStr) > 0) do
    begin
      FList[j + 1] := FList[j];
      j := j - 1;
    end;
    FList[j + 1] := tmp;
  end;
end;

end.
