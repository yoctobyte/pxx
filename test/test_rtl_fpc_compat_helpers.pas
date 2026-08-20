program test_rtl_fpc_compat_helpers;
{$mode objfpc}{$H+}
{ RTL surface FPC code names that this RTL was missing, found by compiling
  rtl-generics (feature-pascal-corpus-generics): SysUtils.CompareMemRange and
  the Wide/Unicode compare pairs, System.DynArraySize, Math.CompareValue, and
  the HRESULT constants, and Variants.VarCompareValue with its
  TVariantRelationship / EVariantError. All of them are called by
  generics.defaults' default comparers, so the whole unit stopped at the first
  one.

  Checked against FPC, which is the point: CompareMemRange must compare bytes
  UNSIGNED (a PChar compare would sort $FF below $01), DynArraySize must answer
  Length() through an untyped pointer, and the Wide/Unicode names must behave as
  the Ansi ones do here — this RTL has one string model, bytes.

  (Oracle note: to RUN this under FPC, put `cwstring` first in the uses clause —
  FPC's WideCompareStr goes through a widestring manager and raises
  ENoWideStringSupport without one. Nothing here needs it under pxx, where the
  Wide names ARE the byte ones. The FPC run agrees, 23/23.)

  The VarCompareValue block was diffed case by case against FPC 3.2.2 (27 pairs,
  identical answers including the two that raise). The one pair NOT checked here
  is Unassigned against Null: FPC answers vrNotEqual, pxx vrEqual, because pxx
  has a single empty tag — the divergence the variants unit header states. }

uses sysutils, math, classes, variants;

var
  total, okc: Integer;

{ VarCompareValue, with the raise folded into the result: vrNotEqual is a real
  answer here, so an incomparable pair needs a value of its own to assert on. }
function Rel(const x, y: Variant): AnsiString;
begin
  Result := 'raise';
  try
    if VarCompareValue(x, y) = vrEqual then Result := 'eq'
    else if VarCompareValue(x, y) = vrLessThan then Result := 'lt'
    else if VarCompareValue(x, y) = vrGreaterThan then Result := 'gt'
    else Result := 'ne';
  except
    on e: EVariantError do Result := 'raise';
  end;
end;

procedure Check(name: string; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

var
  a, b: array[0..3] of Byte;
  d: array of Integer;
  e: array of Integer;
  ch: Char;
begin
  total := 0; okc := 0;

  a[0] := 1; a[1] := 2; a[2] := 3; a[3] := 4;
  b[0] := 1; b[1] := 2; b[2] := 3; b[3] := 4;
  Check('memrange-eq', CompareMemRange(@a, @b, 4) = 0);
  b[2] := 9;
  Check('memrange-lt', CompareMemRange(@a, @b, 4) < 0);
  Check('memrange-gt', CompareMemRange(@b, @a, 4) > 0);
  Check('memrange-prefix', CompareMemRange(@a, @b, 2) = 0);
  { the high byte must sort ABOVE the low one: a SIGNED byte compare inverts it }
  a[0] := 200; b[0] := 1; b[2] := 3;
  Check('memrange-unsigned', CompareMemRange(@a, @b, 4) > 0);

  SetLength(d, 7);
  Check('dynarraysize', DynArraySize(Pointer(d)) = Length(d));
  Check('dynarraysize-nil', DynArraySize(Pointer(e)) = 0);

  Check('widecomparestr-lt', WideCompareStr('abc', 'abd') < 0);
  Check('widecomparetext-eq', WideCompareText('ABC', 'abc') = 0);
  Check('unicodecomparestr-gt', UnicodeCompareStr('b', 'a') > 0);
  Check('unicodecomparetext-eq', UnicodeCompareText('AbC', 'aBc') = 0);

  Check('comparevalue-int', (CompareValue(1, 2) = LessThanValue) and
                            (CompareValue(2, 2) = EqualsValue) and
                            (CompareValue(3, 2) = GreaterThanValue));
  Check('comparevalue-int64', CompareValue(Int64(5), Int64(4)) = 1);
  Check('comparevalue-double', CompareValue(1.5, 2.5) = -1);

  Check('hresult-consts', (S_OK = 0) and (E_NOINTERFACE <> 0));

  Check('varcmp-int', (Rel(1, 2) = 'lt') and (Rel(2, 2) = 'eq') and
                      (Rel(3, 2) = 'gt') and (Rel(2.5, 2) = 'gt'));
  Check('varcmp-str', (Rel('abc', 'abd') = 'lt') and (Rel('abc', 'abc') = 'eq') and
                      (Rel('b', 'a') = 'gt'));
  { text against a number parses the text -- '10' is ten, not the string '10',
    which would sort BELOW '2' }
  Check('varcmp-text-numifies', (Rel('10', 2) = 'gt') and (Rel('1', 1) = 'eq'));
  { booleans order False < True as booleans; against a NUMBER True is -1 }
  Check('varcmp-bool', (Rel(True, False) = 'gt') and (Rel(True, True) = 'eq') and
                       (Rel(True, 1) = 'lt') and (Rel(True, -1) = 'eq'));
  { a char equals the one-character string }
  ch := 'q';
  Check('varcmp-char', (Rel(ch, ch) = 'eq') and (Rel(ch, 'q') = 'eq'));
  { empty on one side is not an ORDERING -- vrNotEqual, both ways round }
  Check('varcmp-empty', (Rel(Null, Null) = 'eq') and (Rel(Null, 1) = 'ne') and
                        (Rel(1, Null) = 'ne'));
  { unparseable text against a number raises, and callers depend on that:
    rtl-generics' TCompare.Variant catches it to fall back to a string compare }
  Check('varcmp-raises', (Rel('abc', 2) = 'raise') and (Rel(2, 'abc') = 'raise'));
  Check('varcmp-i64', Rel(Int64(5000000000), Int64(4999999999)) = 'gt');

  writeln('total ok ', okc, ' / ', total);
end.
