{ SPDX-License-Identifier: Zlib }
unit variants;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ The FPC `Variants` surface, over pxx's own Variant.

  A pxx Variant is a 16-byte tagged value: an 8-byte TAG (the VT_* constants in
  defs.inc) followed by an 8-byte payload interpreted per tag. That is our model, not
  FPC's TVarData, and it is deliberately a closed scalar set -- so this unit exposes the
  parts of Variants that are meaningful over it, and does not pretend to the rest.

  Tag values (VT_*, from the compiler):
    0 empty   1 int   2 int64   3 double   4 boolean   5 char   6 string

  Note 0 = EMPTY, matching FPC's varEmpty, which is what `VarType(v) = 0` tests. FPC
  additionally distinguishes varNull (1) from varEmpty; pxx has no separate NULL tag, so
  VarIsNull and VarIsEmpty are the same question here and both answer "is it unassigned".
  Code that needs a real three-way empty/null/value distinction wants a ticket, not a
  silent approximation -- say so rather than guessing.

  Exists because fcl-json's fpjson.pp does `uses variants`. }

interface

{ sysutils, for Exception (EVariantError's parent) and the string<->number
  conversions VarCompareValue needs when one side is text and the other a
  number. No cycle: sysutils does not use this unit. }
uses sysutils;

type
  TVarType = Word;

  { FPC's variant ordering result (Variants.TVariantRelationship).

    vrNotEqual is NOT a spelling of "different" -- it is the answer when an
    ORDERING is meaningless, which over pxx's tag set means exactly one side
    holds no value. Two values that are merely unequal answer vrLessThan or
    vrGreaterThan. }
  TVariantRelationship = (vrEqual, vrLessThan, vrGreaterThan, vrNotEqual);

  { Raised when the two variants cannot be brought to a common comparable type
    -- text that is not a number, against a number.

    FPC raises the same class from VarCompareValue and callers DEPEND on it:
    rtl-generics' TCompare.Variant wraps the call in try/except and falls back
    to comparing the two as strings, then to a raw memory compare. Answering
    vrNotEqual instead would silently take that fallback away and return an
    ordering derived from emptiness, which neither side is. }
  { RE-EXPORTED, not declared: the class itself moved to sysutils on
    2026-08-21 so the builtin units' PXXVariantErrorHook has something to raise
    in every program, `uses variants` being optional in pxx. Same class object,
    so `on E: EVariantError` written against either unit catches both. }
  EVariantError = sysutils.EVariantError;

{ FPC's Null / Unassigned variant values.

  READ THE UNIT HEADER: pxx has ONE "no value" tag (VT_EMPTY), where FPC distinguishes
  varEmpty (never assigned) from varNull (assigned, but null). So these two return the SAME
  thing here, and `VarIsNull(Unassigned)` is True where FPC says False.

  That is a real approximation and it is stated rather than hidden. It is the right one for
  the callers that exist -- fpjson uses Null purely as "the JSON null value", never to
  distinguish it from unassigned -- but code that genuinely needs the three-way
  empty/null/value distinction wants a compiler change (a VT_NULL tag), not a library
  workaround. Say so rather than quietly returning the wrong answer.

  These are VARIABLES, not functions, because a function cannot return a Variant in this
  compiler yet (bug-variant-function-return -- a Variant result segfaults). FPC declares them
  as functions; as read-only values the difference is invisible to callers, which is the
  whole surface anyone uses. They are initialised empty and nothing writes them. }
var
  Null: Variant;
  Unassigned: Variant;

{ The tag of V (VT_EMPTY..VT_STRING above). }
function VarType(const V: Variant): TVarType;

{ True when V holds no value. pxx has one "no value" tag, so these agree -- see the note
  above. }
function VarIsEmpty(const V: Variant): Boolean;
function VarIsNull(const V: Variant): Boolean;

{ True when V holds a number (integer kinds or a double). }
function VarIsNumeric(const V: Variant): Boolean;

{ True when V holds a string. }
function VarIsStr(const V: Variant): Boolean;

{ Order A against B the way FPC's Variants.VarCompareValue does.

  The rules, in the order they are tried -- each one is an FPC behaviour checked
  against the 3.2.2 oracle, not a guess:

    - no value on either side: vrEqual when BOTH are empty, else vrNotEqual.
      (FPC distinguishes Unassigned from Null here and answers vrNotEqual for
      that pair; pxx has one empty tag, so it answers vrEqual. Same
      approximation the unit header states for VarIsNull -- see it.)
    - two booleans: False < True.
    - two texts (string or char): CompareStr, so a char compares equal to the
      one-character string, as in FPC.
    - text against a boolean: compared as TEXT, with the boolean rendered
      'True'/'False'. Looks arbitrary and is: FPC answers gt for (True, '1'),
      which is 'True' > '1' textually and lt numerically.
    - anything else is compared as a NUMBER. A boolean numifies to -1/0 (FPC's
      value, and pxx's own Variant->Int64 conversion agrees), text numifies by
      parsing, and the comparison is done in Int64 unless a Double is involved.
    - text that will not parse, against a number: EVariantError. That raise is
      part of the contract -- see EVariantError. }
function VarCompareValue(const A, B: Variant): TVariantRelationship;

implementation

const
  { the VT_* tags again, named, so the comparator below reads as intent }
  VT_EMPTY  = 0;
  VT_INT    = 1;
  VT_INT64  = 2;
  VT_DOUBLE = 3;
  VT_BOOL   = 4;
  VT_CHAR   = 5;
  VT_STRING = 6;

type
  PTagWord = ^Int64;

function VarType(const V: Variant): TVarType;
begin
  { the tag is the first machine word of the slot }
  Result := TVarType(PTagWord(@V)^);
end;

function VarIsEmpty(const V: Variant): Boolean;
begin
  Result := VarType(V) = 0;
end;

function VarIsNull(const V: Variant): Boolean;
begin
  Result := VarType(V) = 0;
end;

function VarIsNumeric(const V: Variant): Boolean;
var t: TVarType;
begin
  t := VarType(V);
  Result := (t = 1) or (t = 2) or (t = 3);
end;

function VarIsStr(const V: Variant): Boolean;
begin
  { VT_CHAR counts, and this used to say only `= 6`. IsTextTag right below —
    "a char and a string are one kind here" — already said so for comparison,
    so the unit contained both answers and gave them to different callers.
    FPC has no char variant at all (`v := c` with c: Char gives VarType 256,
    varString), so True is also its answer.
    bug-a-a-char-variant-converts-to-its-ordinal-not-its-text }
  Result := (VarType(V) = VT_STRING) or (VarType(V) = VT_CHAR);
end;

{ text tag: a char and a string are one kind here -- this RTL's Variant holds
  bytes either way, and FPC compares them as text too. }
function IsTextTag(t: TVarType): Boolean;
begin
  Result := (t = VT_STRING) or (t = VT_CHAR);
end;

function CmpInt(a, b: Int64): TVariantRelationship;
begin
  if a < b then Result := vrLessThan
  else if a > b then Result := vrGreaterThan
  else Result := vrEqual;
end;

function CmpDbl(a, b: Double): TVariantRelationship;
begin
  if a < b then Result := vrLessThan
  else if a > b then Result := vrGreaterThan
  else Result := vrEqual;
end;

function CmpStr(const a, b: AnsiString): TVariantRelationship;
var c: Integer;
begin
  c := CompareStr(a, b);
  if c < 0 then Result := vrLessThan
  else if c > 0 then Result := vrGreaterThan
  else Result := vrEqual;
end;

{ V as text, for the text arms: a boolean renders 'True'/'False' (FPC's
  spelling), everything else goes through the compiler's own conversion. }
function AsText(const V: Variant; t: TVarType): AnsiString;
var b: Boolean;
begin
  if t = VT_BOOL then
  begin
    b := V;
    if b then Result := 'True' else Result := 'False';
  end
  else
    Result := V;
end;

{ V as a number: i when isFloat is False, d when it is True. False means V is
  not numifiable -- text that does not parse -- which is the EVariantError case. }
function AsNumber(const V: Variant; t: TVarType; var i: Int64; var d: Double;
                  var isFloat: Boolean): Boolean;
var s: AnsiString; b: Boolean;
begin
  Result := True;
  isFloat := False;
  i := 0;
  d := 0;
  if (t = VT_INT) or (t = VT_INT64) then
    i := V
  else if t = VT_BOOL then
  begin
    b := V;
    { -1, not 1: that is the value FPC's variant boolean carries into a numeric
      compare, and pxx's own Variant->Int64 conversion already agrees. }
    if b then i := -1 else i := 0;
  end
  else if t = VT_DOUBLE then
  begin
    d := V;
    isFloat := True;
  end
  else if IsTextTag(t) then
  begin
    s := V;
    if not TryStrToInt64(s, i) then
    begin
      if TryStrToFloat(s, d) then isFloat := True else Result := False;
    end;
  end
  else
    Result := False;
end;

function VarCompareValue(const A, B: Variant): TVariantRelationship;
var
  ta, tb: TVarType;
  la, lb: Int64;
  da, db: Double;
  fa, fb, oka, okb: Boolean;
begin
  ta := VarType(A);
  tb := VarType(B);

  if (ta = VT_EMPTY) or (tb = VT_EMPTY) then
  begin
    if ta = tb then Result := vrEqual else Result := vrNotEqual;
    Exit;
  end;

  if (ta = VT_BOOL) and (tb = VT_BOOL) then
  begin
    { as booleans, False < True -- NOT as their -1/0 numeric values, which would
      order True below False. FPC answers gt for (True, False). }
    la := 0; if AsText(A, ta) = 'True' then la := 1;
    lb := 0; if AsText(B, tb) = 'True' then lb := 1;
    Result := CmpInt(la, lb);
    Exit;
  end;

  if IsTextTag(ta) and IsTextTag(tb) then
  begin
    Result := CmpStr(AsText(A, ta), AsText(B, tb));
    Exit;
  end;

  if (IsTextTag(ta) and (tb = VT_BOOL)) or ((ta = VT_BOOL) and IsTextTag(tb)) then
  begin
    Result := CmpStr(AsText(A, ta), AsText(B, tb));
    Exit;
  end;

  oka := AsNumber(A, ta, la, da, fa);
  okb := AsNumber(B, tb, lb, db, fb);
  if not (oka and okb) then
    raise EVariantError.Create('VarCompareValue: variants are not comparable');

  if fa or fb then
  begin
    if not fa then da := la;
    if not fb then db := lb;
    Result := CmpDbl(da, db);
  end
  else
    Result := CmpInt(la, lb);
end;

end.
