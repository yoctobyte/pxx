{ SPDX-License-Identifier: Zlib }
unit classes;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
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

uses sysutils, platform{$ifdef PXX_THREADSAFE}, palthreadobj{$endif};
  { CompareStr for Sort; PAL file API for TFileStream. palthreadobj ONLY under
    PXX_THREADSAFE — see the TThread note below. }

{$ifdef PXX_THREADSAFE}
type
  { TThread where FPC and Delphi code looks for it: `uses Classes`, not
    `uses palthreadobj` (compat-pascal-thread-api-surface-differs-from-fpc).

    CONDITIONAL, and it has to be. palthreadobj reaches palthread, which
    contains __pxxclone, and the parser errors on that identifier unless the
    thread-safe runtime is selected — so an unconditional `uses palthreadobj`
    here would break EVERY `uses classes` program that never spawns a thread.
    Measured before it was written: a TStringList-only program failed to
    compile. Gating on PXX_THREADSAFE means a threaded build gets TThread from
    Classes exactly as on FPC, and a non-threaded build never parses palthread.

    An ALIAS, not a redeclaration: pxx's `uses` is not transitive, so the name
    has to be re-exported here for a program that names only Classes. Verified
    that an alias carries full class semantics across units — a program using
    only the aliasing unit can subclass through it and override a virtual. }
  TThread = palthreadobj.TThread;
  TThreadMethod = palthreadobj.TThreadMethod;
  TThreadID = palthreadobj.TThreadID;
  TThreadFunc = palthreadobj.TThreadFunc;
{$endif}

type
  { FPC declares these in Classes. Real classes, not aliases: code catches them by type and
    `is`/`as` must distinguish them. fcl-json's scanner derives EScannerError from EParserError. }
  EParserError    = class(Exception) end;
  EStreamError    = class(Exception) end;
  EComponentError = class(Exception) end;
  EFilerError     = class(EStreamError) end;

  { ---- IInterface: the root interface (FPC declares it in System) ----
    FPC hands every unit IInterface/IUnknown and HResult from System. pxx has no
    auto-injected System unit, so any FPC source that names them — fcl-fpcunit's
    testutils (`TNoRefCountObject = class(TObject, IInterface)`) is the first —
    finds nothing. Declared here because Classes is what such units already use.
    pxx interfaces default to CORBA (no refcounting), so this adds the NAME and
    the three reserved method slots without imposing COM lifetime management. }
  HResult = LongInt;

  IInterface = interface
    ['{00000000-0000-0000-C000-000000000046}']   { the canonical IUnknown GUID }
    function QueryInterface(constref IID: TGuid; out Obj): HResult;
    function _AddRef: Integer;
    function _Release: Integer;
  end;
  IUnknown = IInterface;

const
  { The COM HRESULT codes, for the same reason IInterface and HResult are here:
    FPC hands them to every unit from System, and pxx has no auto-injected
    System unit. A QueryInterface body that refuses an interface returns
    E_NOINTERFACE, which is the first one any FPC source implementing
    IInterface reaches for (rtl-generics' Generics.Defaults does, at
    generics.defaults.pas:1088). Written as signed LongInt values because
    that is what HResult is; $80004002 does not fit a positive LongInt. }
  S_OK          = LongInt(0);
  S_FALSE       = LongInt(1);
  E_NOTIMPL     = LongInt(-2147467263);   { $80004001 }
  E_NOINTERFACE = LongInt(-2147467262);   { $80004002 }
  E_FAIL        = LongInt(-2147467259);   { $80004005 }
  E_UNEXPECTED  = LongInt(-2147418113);   { $8000FFFF }

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

const
  { Delphi's older names for the same three values, which is what most existing
    code writes (FPC accepts both, and Ord() agrees: 0, 1, 2). Aliases rather
    than a second enum, so a Seek written either way is the same call. }
  soFromBeginning = soBeginning;
  soFromCurrent   = soCurrent;
  soFromEnd       = soEnd;

type

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

const
  { TFileStream open modes (FPC/Delphi). Share modes are accepted and ignored
    — this RTL has no locking; the or-composition still type-checks. }
  fmCreate        = $FF00;
  fmOpenRead      = 0;
  fmOpenWrite     = 1;
  fmOpenReadWrite = 2;
  fmShareCompat    = 0;
  fmShareExclusive = $10;
  fmShareDenyWrite = $20;
  fmShareDenyRead  = $30;
  fmShareDenyNone  = $40;

type
  { ---- TStringStream: a stream over a string ----
    FPC's TStringStream is a TStream whose contents ARE a string: construct it with the text
    to read, or write into it and read the accumulated text back out of DataString. fpjson's
    TJSONData.AsJSON formats through one.

    Built on TMemoryStream, which already has the buffer, the growth and the seek discipline
    -- this only adds the string <-> bytes ends. }
  TStringStream = class(TMemoryStream)
  private
    function GetDataString: string;
  public
    constructor Create; overload;
    constructor Create(const AString: string); overload;
    { The stream's bytes, as a string. Reading it does not move Position. }
    property DataString: string read GetDataString;
    { FPC convenience: append text at the current position. }
    procedure WriteString(const AString: string);
    { FPC convenience: read Count bytes from the current position as a string. }
    function ReadString(Count: Longint): string;
  end;

  TFileStream = class(TStream)
  private
    FHandle: Integer;
    FFileName: string;
  protected
    function GetSize: Int64; override;
    function GetPosition: Int64; override;
    procedure SetPosition(const Pos: Int64); override;
  public
    constructor Create(const AFileName: string; Mode: Word);
    destructor Destroy; override;
    function Read(var Buffer; Count: Longint): Longint; override;
    function Write(const Buffer; Count: Longint): Longint; override;
    function Seek(const Offset: Int64; Origin: TSeekOrigin): Int64; override;
    property Handle: Integer read FHandle;
    property FileName: string read FFileName;
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

  { ---- TFPList: FPC's plain pointer list ----
    In FPC, TFPList is the non-notifying pointer list and TList adds the Notify hook
    on top. Our TList already carries exactly TFPList's surface (Add / Clear / Delete
    / Insert / IndexOf / Remove / Count / Items), so TFPList is that list under the
    name FPC sources actually write — fcl-fpcunit's suites are full of it. A
    descendant rather than an alias, so it is a distinct class for `is`/`as` and for
    a parameter typed TFPList. }
  TFPList = class(TList)
  end;

  { ---- TStrings: abstract string-list base ---- }
  TStrings = class
  protected
    function Get(Index: Integer): string; virtual; abstract;
    function GetCount: Integer; virtual; abstract;
    function GetObject(Index: Integer): TObject; virtual; abstract;
    procedure Put(Index: Integer; const S: string); virtual; abstract;
    procedure PutObject(Index: Integer; AObject: TObject); virtual; abstract;
    { THE one place a string comparison is decided, for every lookup on this
      class and its descendants — IndexOf, IndexOfName, Values, and (in
      TStringList) Find, Sort and the sorted Add. Virtual so TStringList can
      make it follow CaseSensitive; case-INSENSITIVE here, which is FPC's
      default for a bare TStrings.

      It lives on TStrings and not on TStringList because it was on TStringList,
      and the lookups that could not reach it grew their own comparisons instead
      — three mechanisms for one concept, disagreeing in BOTH directions:
      IndexOf compared with `=` and so stayed case-sensitive when the flag said
      otherwise, while IndexOfName hardcoded SameText and stayed
      case-insensitive when the flag said otherwise. Only Find/Sort were right.
      ([[bug-b-tstringlist-lookups-use-three-different-comparisons]]) }
    function CompareStrings(const S1, S2: string): Integer; virtual;
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
    { ---- the Name=Value surface ----
      A TStrings doubles as a string-keyed map in FPC and Delphi, and real
      source leans on it hard: Synapse's cookie jar is
      `FCookies.Values[name] := v` and nothing else. The separator is a
      settable field because FPC exposes it and `:` shows up in header
      parsers; the constructor gives it FPC's default. Name matching is
      CASE-INSENSITIVE, as FPC's is. }
    NameValueSeparator: Char;

    { ---- the CommaText / DelimitedText surface ----
      A TStrings is also how FPC code parses and emits a delimited line, and
      the QUOTING RULES are the whole job. Read off an FPC build case by case,
      because none of them is obvious from the description:

      Writing: an item is quoted when it contains the Delimiter, the QuoteChar,
      or — unless StrictDelimiter — any character <= ' '. An embedded QuoteChar
      is DOUBLED. An empty item normally writes as nothing (`a,,b`), with one
      exception: a list of exactly one empty string writes as `""`, which is
      what keeps it distinguishable from an empty list. A list with no items
      writes as ''.

      Reading: a quoted section is taken literally with doubled QuoteChars
      collapsed. Unless StrictDelimiter, WHITESPACE ALSO SEPARATES — `a b,c d`
      parses to FOUR items, not two — and space around an item is dropped. Under
      StrictDelimiter only the Delimiter separates and spacing is preserved.

      CommaText is DelimitedText pinned to ',' and '"' and forced NON-strict,
      and reading or writing it does NOT disturb Delimiter/QuoteChar/
      StrictDelimiter. }
    Delimiter: Char;
    QuoteChar: Char;
    StrictDelimiter: Boolean;
    function BuildDelimited(delim, quote: Char; strict: Boolean): string;
    procedure ParseDelimited(const Value: string; delim, quote: Char; strict: Boolean);
    function GetDelimitedText: string;
    procedure SetDelimitedText(const Value: string);
    function GetCommaText: string;
    procedure SetCommaText(const Value: string);

    constructor Create;
    function IndexOfName(const Name: string): Integer; virtual;
    function GetName(Index: Integer): string;
    function GetValue(const Name: string): string;
    procedure SetValue(const Name, Value: string);
    function GetValueFromIndex(Index: Integer): string;
    procedure SetValueFromIndex(Index: Integer; const Value: string);
    property Count: Integer read GetCount;
    property Strings[Index: Integer]: string read Get write Put; default;
    property Objects[Index: Integer]: TObject read GetObject write PutObject;
    property Text: string read GetText write SetText;
    property DelimitedText: string read GetDelimitedText write SetDelimitedText;
    property CommaText: string read GetCommaText write SetCommaText;
    property Names[Index: Integer]: string read GetName;
    { Assigning an empty value here keeps `Name=` with an empty value; it is
      ValueFromIndex that deletes. Both follow FPC, measured. }
    property Values[const Name: string]: string read GetValue write SetValue;
    property ValueFromIndex[Index: Integer]: string
      read GetValueFromIndex write SetValueFromIndex;
  end;

  { ---- TStringList: concrete string list with paired objects ---- }
  TStringItem = record
    FStr: string;
    FObj: TObject;
  end;

  { FPC's TStringList duplicate policy, meaningful only while Sorted:
    dupIgnore drops a repeat, dupError raises, dupAccept keeps both. }
  TDuplicates = (dupIgnore, dupAccept, dupError);

  TStringList = class(TStrings)
  private
    FList: array of TStringItem;
    FCount: Integer;
    FSorted: Boolean;
    FDuplicates: TDuplicates;
    FCaseSensitive: Boolean;
    procedure SetSorted(Value: Boolean);
    procedure SetCaseSensitive(Value: Boolean);
    procedure InsertItem(Index: Integer; const S: string);
  protected
    function Get(Index: Integer): string; override;
    function GetCount: Integer; override;
    function GetObject(Index: Integer): TObject; override;
    procedure Put(Index: Integer; const S: string); override;
    procedure PutObject(Index: Integer; AObject: TObject); override;
    { Follows CaseSensitive. FPC compares case-INSENSITIVELY unless it is set,
      which is why `Sort` on (Banana, apple, Cherry) yields apple, Banana,
      Cherry and not the ASCII order. Overriding TStrings' virtual is what makes
      the INHERITED lookups (IndexOf, IndexOfName, Values) follow the flag too. }
    function CompareStrings(const S1, S2: string): Integer; override;
  public
    constructor Create;
    procedure Clear; override;
    procedure Delete(Index: Integer); override;
    procedure Insert(Index: Integer; const S: string); override;
    function Add(const S: string): Integer; override;
    function IndexOf(const S: string): Integer; override;
    { Binary search over a sorted list. Returns whether S is present; Index is
      where it is, or where it WOULD be inserted when it is not — that second
      use is what the sorted Add needs, so the two cannot drift apart. }
    function Find(const S: string; var Index: Integer): Boolean;
    procedure Sort;
    property Sorted: Boolean read FSorted write SetSorted;
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property CaseSensitive: Boolean read FCaseSensitive write SetCaseSensitive;
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

{ ============================ TStringStream =========================== }

constructor TStringStream.Create;
begin
  { an empty stream, ready to be written into }
end;

constructor TStringStream.Create(const AString: string);
begin
  if Length(AString) > 0 then
    Self.Write(AString[1], Length(AString));
  Position := 0;      { FPC: a string-constructed stream starts at the beginning }
end;

function TStringStream.GetDataString: string;
var
  n: Longint;
  savedPos: Int64;
begin
  Result := '';
  n := Longint(Size);
  if n <= 0 then Exit;
  SetLength(Result, n);
  savedPos := Position;         { reading DataString must not move Position }
  Position := 0;
  Self.Read(Result[1], n);      { Self-qualified: bare `Read` is the console intrinsic }
  Position := savedPos;
end;

procedure TStringStream.WriteString(const AString: string);
begin
  if Length(AString) > 0 then
    Self.Write(AString[1], Length(AString));
end;

function TStringStream.ReadString(Count: Longint): string;
var got: Longint;
begin
  Result := '';
  if Count <= 0 then Exit;
  SetLength(Result, Count);
  got := Self.Read(Result[1], Count);
  if got < Count then SetLength(Result, got);
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

constructor TFileStream.Create(const AFileName: string; Mode: Word);
var flags: Integer;
begin
  inherited Create;
  FFileName := AFileName;
  if (Mode and fmCreate) = fmCreate then
    flags := PAL_OPEN_RDWR or PAL_OPEN_CREATE or PAL_OPEN_TRUNC
  else
    case Mode and 3 of
      fmOpenWrite:     flags := PAL_OPEN_WRITE;
      fmOpenReadWrite: flags := PAL_OPEN_RDWR;
    else
      flags := PAL_OPEN_READ;
    end;
  FHandle := PalOpen(PChar(AFileName), flags, 438);   { 0666 }
  if FHandle < 0 then
    raise Exception.Create('TFileStream: cannot open ' + AFileName);
end;

destructor TFileStream.Destroy;
begin
  if FHandle >= 0 then PalClose(FHandle);
  FHandle := -1;
  inherited Destroy;
end;

function TFileStream.Read(var Buffer; Count: Longint): Longint;
begin
  Result := Longint(PalRead(FHandle, @Buffer, Count));
  if Result < 0 then Result := 0;
end;

function TFileStream.Write(const Buffer; Count: Longint): Longint;
begin
  Result := Longint(PalWrite(FHandle, @Buffer, Count));
  if Result < 0 then Result := 0;
end;

function TFileStream.Seek(const Offset: Int64; Origin: TSeekOrigin): Int64;
var whence: Integer;
begin
  case Origin of
    soCurrent: whence := PAL_SEEK_CUR;
    soEnd:     whence := PAL_SEEK_END;
  else
    whence := PAL_SEEK_SET;
  end;
  Result := PalSeek(FHandle, Offset, whence);
end;

function TFileStream.GetSize: Int64;
var cur: Int64;
begin
  cur := PalSeek(FHandle, 0, PAL_SEEK_CUR);
  Result := PalSeek(FHandle, 0, PAL_SEEK_END);
  PalSeek(FHandle, cur, PAL_SEEK_SET);
end;

function TFileStream.GetPosition: Int64;
begin
  Result := PalSeek(FHandle, 0, PAL_SEEK_CUR);
end;

procedure TFileStream.SetPosition(const Pos: Int64);
begin
  PalSeek(FHandle, Pos, PAL_SEEK_SET);
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

{ Through CompareStrings, not `=`: with a plain `=` this ignored TStringList's
  CaseSensitive entirely and answered -1 for a string that was present under a
  different case — where FPC, whose default is case-insensitive, finds it. }
function TStrings.IndexOf(const S: string): Integer;
var i: Integer;
begin
  for i := 0 to GetCount - 1 do
    if CompareStrings(Get(i), S) = 0 then begin Result := i; Exit; end;
  Result := -1;
end;

{ TStrings' own comparison: case-insensitive, FPC's default. TStringList
  overrides this to follow CaseSensitive. }
function TStrings.CompareStrings(const S1, S2: string): Integer;
begin
  Result := CompareText(S1, S2);
end;

{ The separator is the PLATFORM one (LineEnding: LF here, and a
  compiler-known constant so it follows the target), not a hardcoded CRLF.
  FPC's TStrings.GetTextStr does the same, so a two-line list is 4 bytes on
  Linux, not 6 — and SaveToFile through here was writing DOS line endings into
  files on a Unix host. SetText below already accepts either form, which is why
  the round-trip hid this. }
function TStrings.GetText: string;
var i: Integer; r: string;
begin
  r := '';
  for i := 0 to GetCount - 1 do r := r + Get(i) + LineEnding;
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

constructor TStrings.Create;
begin
  NameValueSeparator := '=';
  Delimiter := ',';
  QuoteChar := '"';
  StrictDelimiter := False;
end;

{ The shared engine for both properties: CommaText is this with the delimiter,
  quote and strictness pinned, which is why they are parameters here rather than
  reads of the fields. }
function TStrings.BuildDelimited(delim, quote: Char; strict: Boolean): string;
var
  i, j: Integer;
  item, r: string;
  needQuote: Boolean;
  ch: Char;
begin
  r := '';
  { FPC's one special case: a single empty string must not render as '', or it
    would be indistinguishable from a list with no items at all. }
  if (GetCount = 1) and (Get(0) = '') then
  begin
    Result := quote + quote;
    Exit;
  end;
  for i := 0 to GetCount - 1 do
  begin
    if i > 0 then r := r + delim;
    item := Get(i);
    needQuote := False;
    for j := 1 to Length(item) do
    begin
      ch := item[j];
      if (ch = delim) or (ch = quote) or ((not strict) and (ch <= ' ')) then
      begin
        needQuote := True;
        Break;
      end;
    end;
    if needQuote then
    begin
      r := r + quote;
      for j := 1 to Length(item) do
      begin
        ch := item[j];
        if ch = quote then r := r + quote;   { doubled, not escaped }
        r := r + ch;
      end;
      r := r + quote;
    end
    else
      r := r + item;
  end;
  Result := r;
end;

procedure TStrings.ParseDelimited(const Value: string; delim, quote: Char;
                                  strict: Boolean);
var
  i, n: Integer;
  item: string;
  ch: Char;
begin
  Clear;
  n := Length(Value);
  i := 1;
  { An empty (or, when non-strict, all-whitespace) input is a list of NO items,
    not a list of one empty item. }
  if not strict then
    while (i <= n) and (Value[i] <= ' ') do i := i + 1;
  if i > n then Exit;
  while i <= n do
  begin
    item := '';
    { The quote is special ONLY at the start of an item, and the closing quote
      ENDS the item — measured, both directions:
        `"a"b`  -> two items <a> <b>   (closing quote terminates, b starts anew)
        `a"b"`  -> one item <a"b">     (a quote mid-item is a literal character)
      Getting this from the description rather than from FPC produced <ab> for
      both, which round-trips fine and is wrong twice. }
    if Value[i] = quote then
    begin
      i := i + 1;
      while i <= n do
      begin
        if Value[i] = quote then
        begin
          if (i < n) and (Value[i + 1] = quote) then
          begin
            item := item + quote;            { doubled quote = one literal }
            i := i + 2;
          end
          else
          begin
            i := i + 1;                      { closing quote ends the item }
            Break;
          end;
        end
        else
        begin
          item := item + Value[i];
          i := i + 1;
        end;
      end;
    end
    else
      while i <= n do
      begin
        ch := Value[i];
        if ch = delim then Break;
        if (not strict) and (ch <= ' ') then Break;   { whitespace separates too }
        item := item + ch;
        i := i + 1;
      end;
    Add(item);
    { Consume the separator. Non-strict, a run of whitespace and at most one
      delimiter count as ONE separator, which is what makes `a, b` two items
      rather than three. }
    if not strict then
    begin
      while (i <= n) and (Value[i] <= ' ') do i := i + 1;
      if (i <= n) and (Value[i] = delim) then
      begin
        i := i + 1;
        while (i <= n) and (Value[i] <= ' ') do i := i + 1;
        if i > n then Add('');               { trailing delimiter = empty item }
      end;
    end
    else if i <= n then
    begin
      i := i + 1;                            { the delimiter itself }
      if i > n then Add('');
    end;
  end;
end;

function TStrings.GetDelimitedText: string;
begin
  Result := BuildDelimited(Delimiter, QuoteChar, StrictDelimiter);
end;

procedure TStrings.SetDelimitedText(const Value: string);
begin
  ParseDelimited(Value, Delimiter, QuoteChar, StrictDelimiter);
end;

function TStrings.GetCommaText: string;
begin
  Result := BuildDelimited(',', '"', False);
end;

procedure TStrings.SetCommaText(const Value: string);
begin
  ParseDelimited(Value, ',', '"', False);
end;

{ FPC's own rule, measured against an FPC build rather than assumed: the
  separator is looked for from position 1, and a line with NO separator has an
  empty Name — its whole text is then the Value. }
function TStrings.GetName(Index: Integer): string;
var s: string; p: Integer;
begin
  s := Get(Index);
  p := Pos(NameValueSeparator, s);
  if p = 0 then GetName := ''
  else GetName := Copy(s, 1, p - 1);
end;

function TStrings.GetValueFromIndex(Index: Integer): string;
var s, n: string;
begin
  s := Get(Index);
  n := GetName(Index);
  if n = '' then GetValueFromIndex := s
  else GetValueFromIndex := Copy(s, Length(n) + 2, Length(s));
end;

{ Note the asymmetry with SetValue below, which is FPC's and not a slip:
  assigning an empty value THROUGH THE INDEX deletes the line, while assigning
  one through the NAME keeps `Name=` with an empty value. }
procedure TStrings.SetValueFromIndex(Index: Integer; const Value: string);
begin
  if Value = '' then Delete(Index)
  else Put(Index, GetName(Index) + NameValueSeparator + Value);
end;

function TStrings.IndexOfName(const Name: string): Integer;
var i, p: Integer; s: string;
begin
  IndexOfName := -1;
  for i := 0 to GetCount - 1 do
  begin
    s := Get(i);
    p := Pos(NameValueSeparator, s);
    if (p > 0) and (CompareStrings(Copy(s, 1, p - 1), Name) = 0) then
    begin
      IndexOfName := i;
      Exit;
    end;
  end;
end;

function TStrings.GetValue(const Name: string): string;
var i: Integer;
begin
  i := IndexOfName(Name);
  if i < 0 then GetValue := ''
  else GetValue := GetValueFromIndex(i);
end;

procedure TStrings.SetValue(const Name, Value: string);
var i: Integer;
begin
  i := IndexOfName(Name);
  if i < 0 then Add(Name + NameValueSeparator + Value)
  else Put(i, Name + NameValueSeparator + Value);
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
begin
  { Placing a string at a caller-chosen index would break the ordering Find's
    binary search depends on, so FPC refuses it outright rather than silently
    leaving the list unsorted-but-marked-sorted. Add is the sorted entry point. }
  if FSorted then
    raise Exception.Create('TStringList: Insert not allowed on a sorted list');
  InsertItem(Index, S);
end;

constructor TStringList.Create;
begin
  inherited Create;
  FSorted := False;
  FDuplicates := dupIgnore;      { FPC's default }
  FCaseSensitive := False;       { FPC's default: comparisons ignore case }
end;

function TStringList.CompareStrings(const S1, S2: string): Integer;
begin
  if FCaseSensitive then Result := CompareStr(S1, S2)
  else Result := CompareText(S1, S2);
end;

procedure TStringList.SetCaseSensitive(Value: Boolean);
begin
  if Value = FCaseSensitive then Exit;
  FCaseSensitive := Value;
  { The ordering just changed underneath a sorted list, so it has to be
    re-established or Find's binary search would walk a list that is no longer
    ordered by the current comparison and report a miss for a present string. }
  if FSorted then
  begin
    FSorted := False;
    Sort;
    FSorted := True;
  end;
end;

procedure TStringList.SetSorted(Value: Boolean);
begin
  if Value = FSorted then Exit;
  if Value then Sort;
  { Clearing Sorted does NOT restore the original order — FPC leaves the list
    as it stands and simply stops maintaining it. }
  FSorted := Value;
end;

function TStringList.Find(const S: string; var Index: Integer): Boolean;
var lo, hi, mid, c: Integer;
begin
  Result := False;
  lo := 0;
  hi := FCount - 1;
  while lo <= hi do
  begin
    mid := lo + (hi - lo) div 2;
    c := CompareStrings(FList[mid].FStr, S);
    if c < 0 then lo := mid + 1
    else if c > 0 then hi := mid - 1
    else
    begin
      Index := mid;
      Result := True;
      Exit;
    end;
  end;
  Index := lo;          { the insertion point when absent }
end;

{ The raw insert, with no sorted-list guard — Add uses it to place a string at
  the position Find chose, which TStringList.Insert itself refuses to do. }
procedure TStringList.InsertItem(Index: Integer; const S: string);
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

function TStringList.Add(const S: string): Integer;
var idx: Integer;
begin
  if not FSorted then
  begin
    Result := FCount;
    InsertItem(Result, S);
    Exit;
  end;
  idx := 0;
  if Find(S, idx) then
  begin
    { Already present. dupIgnore hands back the EXISTING index rather than
      adding — so AddObject on a duplicate retargets the object, as in FPC. }
    if FDuplicates = dupIgnore then begin Result := idx; Exit; end;
    if FDuplicates = dupError then
      raise Exception.Create('TStringList: duplicate string ''' + S + '''');
  end;
  InsertItem(idx, S);
  Result := idx;
end;

function TStringList.IndexOf(const S: string): Integer;
var idx: Integer;
begin
  if FSorted then
  begin
    idx := 0;
    if Find(S, idx) then Result := idx else Result := -1;
    Exit;
  end;
  Result := inherited IndexOf(S);
end;

procedure TStringList.Sort;
var i, j: Integer; tmp: TStringItem;
begin
  { FPC does nothing here when the list is already Sorted — it is maintained
    ordered on every Add, so re-sorting is at best wasted and at worst hides a
    comparison change that should have gone through SetCaseSensitive. }
  if FSorted then Exit;
  { insertion sort, through CompareStrings so the ordering matches Find }
  for i := 1 to FCount - 1 do
  begin
    tmp := FList[i];
    j := i - 1;
    while (j >= 0) and (CompareStrings(FList[j].FStr, tmp.FStr) > 0) do
    begin
      FList[j + 1] := FList[j];
      j := j - 1;
    end;
    FList[j + 1] := tmp;
  end;
end;

end.
