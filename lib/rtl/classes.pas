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
  { ---- TStream: abstract byte stream + TMemoryStream concrete ---- }
  TSeekOrigin = (soBeginning, soCurrent, soEnd);

  TStream = class
  protected
    function GetSize: Int64; virtual;
    function GetPosition: Int64; virtual;
    procedure SetPosition(const Pos: Int64); virtual;
  public
    function Read(var Buffer; Count: Longint): Longint; virtual; abstract;
    function Write(const Buffer; Count: Longint): Longint; virtual; abstract;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; virtual; abstract;
    procedure ReadBuffer(var Buffer; Count: Longint);
    procedure WriteBuffer(const Buffer; Count: Longint);
    function CopyFrom(Source: TStream; Count: Int64): Int64;
    property Position: Int64 read GetPosition write SetPosition;
    property Size: Int64 read GetSize;
  end;

  TMemoryStream = class(TStream)
  private
    FData: array of Byte;
    FSize: Int64;
    FPosition: Int64;
    procedure EnsureCapacity(needed: Int64);
  protected
    function GetSize: Int64; override;
  public
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    procedure Clear;
    procedure SetSize(NewSize: Int64);
    function Memory: Pointer;
  end;

  { ---- TList: a growable list of untyped pointers ---- }
  TList = class
  private
    FItems: array of Pointer;
    FCount: Integer;
    function GetItem(Index: Integer): Pointer;
    procedure SetItem(Index: Integer; Item: Pointer);
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

function TStream.GetSize: Int64;
var p: Int64;
begin
  p := Seek(0, soCurrent);
  Result := Seek(0, soEnd);
  Seek(p, soBeginning);
end;

procedure TStream.ReadBuffer(var Buffer; Count: Longint);
begin
  Self.Read(Buffer, Count);       { Self. — bare Read/Write hit the console intrinsic }
end;

procedure TStream.WriteBuffer(const Buffer; Count: Longint);
begin
  Self.Write(Buffer, Count);
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
    Self.Write(buf[0], got);       { Self. — else the console Write intrinsic }
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
end;

procedure TList.Clear;
begin
  SetLength(FItems, 0);
  FCount := 0;
end;

procedure TList.Delete(Index: Integer);
var i: Integer;
begin
  if (Index < 0) or (Index >= FCount) then Exit;
  for i := Index to FCount - 2 do FItems[i] := FItems[i + 1];
  FCount := FCount - 1;
end;

procedure TList.Insert(Index: Integer; Item: Pointer);
var i: Integer;
begin
  if (Index < 0) or (Index > FCount) then Exit;
  Add(nil);                                  { grow by one }
  for i := FCount - 1 downto Index + 1 do FItems[i] := FItems[i - 1];
  FItems[Index] := Item;
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
