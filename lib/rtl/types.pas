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
  TPoint = record
    X: LongInt;
    Y: LongInt;
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
  end;

  PRect = ^TRect;
  TRect = record
    Left: LongInt;
    Top: LongInt;
    Right: LongInt;
    Bottom: LongInt;
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
