{ SPDX-License-Identifier: Zlib }
unit types;

{ Standard FPC-compatible System.Types surface: the small geometry records
  (TPoint/TSize/TRect/TSmallPoint), the ordinal-comparison relationship type, and
  TDuplicates. Deliberately minimal + extendable — this is the common core real
  FPC/FCL units (`fgl` wants TDuplicates, GUI code wants TPoint/TRect) pull via
  `uses Types`. Grow it as consumers need more; no libc, no PAL. }

interface

type
  { -1 / 0 / +1 comparison result (Math.CompareValue, list sorters). }
  TValueRelationship = -1..1;

  { List insert policy on a duplicate key (fgl / TStringList.Duplicates). }
  TDuplicates = (dupIgnore, dupAccept, dupError);

  PPoint = ^TPoint;
  { An ADVANCED RECORD, as in FPC: TPoint carries its own methods. Self is the record, by
    reference, so Offset/SetLocation mutate the receiver. }
  TPoint = record
    X: LongInt;
    Y: LongInt;
  public
    procedure SetLocation(ax, ay: LongInt); overload;
    procedure SetLocation(const apt: TPoint); overload;
    procedure Offset(dx, dy: LongInt); overload;
    procedure Offset(const apt: TPoint); overload;
    function IsZero: Boolean;
    function Add(const apt: TPoint): TPoint;
    function Subtract(const apt: TPoint): TPoint;
  end;

  PSmallPoint = ^TSmallPoint;
  TSmallPoint = record
    X: SmallInt;
    Y: SmallInt;
  end;

  PSize = ^TSize;
  TSize = record
    cx: LongInt;
    cy: LongInt;
  public
    property Width: LongInt read cx write cx;
    property Height: LongInt read cy write cy;
  end;

  PRect = ^TRect;
  TRect = record
    Left: LongInt;
    Top: LongInt;
    Right: LongInt;
    Bottom: LongInt;
  public
    function GetWidth: LongInt;
    function GetHeight: LongInt;
    function IsEmpty: Boolean;
    function Contains(const apt: TPoint): Boolean;
    property Width: LongInt read GetWidth;
    property Height: LongInt read GetHeight;
  end;

const
  LessThanValue    = TValueRelationship(-1);
  EqualsValue      = TValueRelationship(0);
  GreaterThanValue = TValueRelationship(1);

function Point(AX, AY: LongInt): TPoint;
function SmallPoint(AX, AY: SmallInt): TSmallPoint;
function Size(ACX, ACY: LongInt): TSize;
function Rect(ALeft, ATop, ARight, ABottom: LongInt): TRect;
function Bounds(ALeft, ATop, AWidth, AHeight: LongInt): TRect;
function RectWidth(const R: TRect): LongInt;
function RectHeight(const R: TRect): LongInt;

implementation

procedure TPoint.SetLocation(ax, ay: LongInt);
begin
  X := ax;
  Y := ay;
end;

procedure TPoint.SetLocation(const apt: TPoint);
begin
  X := apt.X;
  Y := apt.Y;
end;

procedure TPoint.Offset(dx, dy: LongInt);
begin
  X := X + dx;
  Y := Y + dy;
end;

procedure TPoint.Offset(const apt: TPoint);
begin
  X := X + apt.X;
  Y := Y + apt.Y;
end;

function TPoint.IsZero: Boolean;
begin
  Result := (X = 0) and (Y = 0);
end;

function TPoint.Add(const apt: TPoint): TPoint;
begin
  Result.X := X + apt.X;
  Result.Y := Y + apt.Y;
end;

function TPoint.Subtract(const apt: TPoint): TPoint;
begin
  Result.X := X - apt.X;
  Result.Y := Y - apt.Y;
end;

function TRect.GetWidth: LongInt;
begin
  Result := Right - Left;
end;

function TRect.GetHeight: LongInt;
begin
  Result := Bottom - Top;
end;

function TRect.IsEmpty: Boolean;
begin
  Result := (Right <= Left) or (Bottom <= Top);
end;

function TRect.Contains(const apt: TPoint): Boolean;
begin
  Result := (apt.X >= Left) and (apt.X < Right) and
            (apt.Y >= Top) and (apt.Y < Bottom);
end;

function Point(AX, AY: LongInt): TPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function SmallPoint(AX, AY: SmallInt): TSmallPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

function Size(ACX, ACY: LongInt): TSize;
begin
  Result.cx := ACX;
  Result.cy := ACY;
end;

function Rect(ALeft, ATop, ARight, ABottom: LongInt): TRect;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ARight;
  Result.Bottom := ABottom;
end;

function Bounds(ALeft, ATop, AWidth, AHeight: LongInt): TRect;
begin
  Result.Left := ALeft;
  Result.Top := ATop;
  Result.Right := ALeft + AWidth;
  Result.Bottom := ATop + AHeight;
end;

function RectWidth(const R: TRect): LongInt;
begin
  Result := R.Right - R.Left;
end;

function RectHeight(const R: TRect): LongInt;
begin
  Result := R.Bottom - R.Top;
end;

end.
