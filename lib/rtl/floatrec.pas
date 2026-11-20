unit floatrec;
{ FPC's System-unit float views, TSingleRec and TDoubleRec, with
  TFloatSpecial. FPC declares them in rtl/inc/mathh.inc, which systemh.inc
  includes, so real code names them with no `uses` at all: the FPC compiler's
  own x86_64/cpuinfo.pas writes `bestrealrec = TDoubleRec`, and nadd.pas asks
  `bestrealrec(v).SpecialType` / `.Mantissa`. pxx has no System unit, so the
  compiler loads this unit when a program or unit NAMES one of these types
  (the token scans in ParseProgram and the unit loader, beside `math`'s).

  Written for pxx from the documented FPC interface (same names, layout and
  results). Not copied from the FPC RTL.
  feature-b-rtl-has-no-tdoublerec }

{$mode objfpc}
{$modeswitch advancedrecords}

interface

type
  TFloatSpecial = (fsZero, fsNZero, fsDenormal, fsNDenormal, fsPositive,
                   fsNegative, fsInf, fsNInf, fsNaN, fsInvalidOp);

  TSingleRec = packed record
  private
    function GetExp: QWord;
    procedure SetExp(e: QWord);
    function GetSign: Boolean;
    procedure SetSign(s: Boolean);
    function GetFrac: QWord;
    procedure SetFrac(e: QWord);
  public
    function Mantissa(IncludeHiddenBit: Boolean = False): QWord;
    function Exponent: Longint;
    function SpecialType: TFloatSpecial;
    procedure BuildUp(const _Sign: Boolean; const _Mantissa: QWord; const _Exponent: Longint);
    property Sign: Boolean read GetSign write SetSign;
    property Exp: QWord read GetExp write SetExp;
    property Frac: QWord read GetFrac write SetFrac;
  case Byte of
    0: (Bytes: array[0..3] of Byte);
    1: (Words: array[0..1] of Word);
    2: (Data: DWord);
    3: (Value: Single);
  end;

  TDoubleRec = packed record
  private
    function GetExp: QWord;
    procedure SetExp(e: QWord);
    function GetSign: Boolean;
    procedure SetSign(s: Boolean);
    function GetFrac: QWord;
    procedure SetFrac(e: QWord);
  public
    function Mantissa(IncludeHiddenBit: Boolean = False): QWord;
    function Fraction: Double;
    function Exponent: Longint;
    function SpecialType: TFloatSpecial;
    procedure BuildUp(const _Sign: Boolean; const _Mantissa: QWord; const _Exponent: Longint);
    property Sign: Boolean read GetSign write SetSign;
    property Exp: QWord read GetExp write SetExp;
    property Frac: QWord read GetFrac write SetFrac;
  case Byte of
    0: (Bytes: array[0..7] of Byte);
    1: (Words: array[0..3] of Word);
    2: (Data: QWord);
    3: (Value: Double);
  end;

implementation

const
  SglBias = 127;
  SglFracMask = $7FFFFF;
  DblBias = 1023;
  DblFracMask = QWord($FFFFFFFFFFFFF);

function ClassifyBits(neg: Boolean; e, emax: QWord; mant: QWord): TFloatSpecial;
begin
  if e = 0 then
  begin
    if mant = 0 then
    begin
      if neg then Result := fsNZero else Result := fsZero;
    end
    else if neg then Result := fsNDenormal
    else Result := fsDenormal;
  end
  else if e = emax then
  begin
    if mant <> 0 then Result := fsNaN
    else if neg then Result := fsNInf
    else Result := fsInf;
  end
  else if neg then Result := fsNegative
  else Result := fsPositive;
end;

{ ---- TSingleRec ---- }

function TSingleRec.GetExp: QWord;
begin
  Result := (Data shr 23) and $FF;
end;

procedure TSingleRec.SetExp(e: QWord);
begin
  Data := (Data and $807FFFFF) or (DWord(e and $FF) shl 23);
end;

function TSingleRec.GetSign: Boolean;
begin
  Result := (Data and $80000000) <> 0;
end;

procedure TSingleRec.SetSign(s: Boolean);
begin
  if s then Data := Data or $80000000
  else Data := Data and $7FFFFFFF;
end;

function TSingleRec.GetFrac: QWord;
begin
  Result := Data and SglFracMask;
end;

procedure TSingleRec.SetFrac(e: QWord);
begin
  Data := (Data and $FF800000) or DWord(e and SglFracMask);
end;

function TSingleRec.Mantissa(IncludeHiddenBit: Boolean): QWord;
begin
  Result := Data and SglFracMask;
  if (Result = 0) and (GetExp = 0) then Exit;
  if IncludeHiddenBit then Result := Result or $800000;
end;

function TSingleRec.Exponent: Longint;
var e: QWord;
begin
  Result := 0;
  e := GetExp;
  if (e > 0) and (e < 2 * SglBias + 1) then
    Result := Longint(e) - SglBias
  else if (e = 0) and (GetFrac <> 0) then
    Result := -(SglBias - 1);
end;

function TSingleRec.SpecialType: TFloatSpecial;
begin
  Result := ClassifyBits(GetSign, GetExp, $FF, GetFrac);
end;

procedure TSingleRec.BuildUp(const _Sign: Boolean; const _Mantissa: QWord; const _Exponent: Longint);
begin
  Data := 0;
  SetSign(_Sign);
  if (_Mantissa = 0) and (_Exponent = 0) then Exit;
  SetExp(QWord(_Exponent + SglBias));
  SetFrac(_Mantissa);
end;

{ ---- TDoubleRec ---- }

function TDoubleRec.GetExp: QWord;
begin
  Result := (Data shr 52) and $7FF;
end;

procedure TDoubleRec.SetExp(e: QWord);
begin
  Data := (Data and QWord($800FFFFFFFFFFFFF)) or ((e and $7FF) shl 52);
end;

function TDoubleRec.GetSign: Boolean;
begin
  Result := (Data shr 63) <> 0;
end;

procedure TDoubleRec.SetSign(s: Boolean);
begin
  Data := (Data and QWord($7FFFFFFFFFFFFFFF)) or (QWord(Ord(s)) shl 63);
end;

function TDoubleRec.GetFrac: QWord;
begin
  Result := Data and DblFracMask;
end;

procedure TDoubleRec.SetFrac(e: QWord);
begin
  Data := (Data and QWord($FFF0000000000000)) or (e and DblFracMask);
end;

function TDoubleRec.Mantissa(IncludeHiddenBit: Boolean): QWord;
begin
  Result := Data and DblFracMask;
  if (Result = 0) and (GetExp = 0) then Exit;
  if IncludeHiddenBit then Result := Result or QWord($10000000000000);
end;

function TDoubleRec.Fraction: Double;
begin
  { System.Frac(Value): the part after the point, sign kept }
  Result := Value - Int(Value);
end;

function TDoubleRec.Exponent: Longint;
var e: QWord;
begin
  Result := 0;
  e := GetExp;
  if (e > 0) and (e < 2 * DblBias + 1) then
    Result := Longint(e) - DblBias
  else if (e = 0) and (GetFrac <> 0) then
    Result := -(DblBias - 1);
end;

function TDoubleRec.SpecialType: TFloatSpecial;
begin
  Result := ClassifyBits(GetSign, GetExp, $7FF, GetFrac);
end;

procedure TDoubleRec.BuildUp(const _Sign: Boolean; const _Mantissa: QWord; const _Exponent: Longint);
begin
  Data := 0;
  SetSign(_Sign);
  if (_Mantissa = 0) and (_Exponent = 0) then Exit;
  SetExp(QWord(_Exponent + DblBias));
  SetFrac(_Mantissa);
end;

end.
