program test_rtl_fpc_compat_helpers;
{ RTL surface FPC code names that this RTL was missing, found by compiling
  rtl-generics (feature-pascal-corpus-generics): SysUtils.CompareMemRange and
  the Wide/Unicode compare pairs, System.DynArraySize, Math.CompareValue, and
  the HRESULT constants. All of them are called by generics.defaults' default
  comparers, so the whole unit stopped at the first one.

  Checked against FPC, which is the point: CompareMemRange must compare bytes
  UNSIGNED (a PChar compare would sort $FF below $01), DynArraySize must answer
  Length() through an untyped pointer, and the Wide/Unicode names must behave as
  the Ansi ones do here — this RTL has one string model, bytes.

  (Oracle note: to RUN this under FPC, put `cwstring` first in the uses clause —
  FPC's WideCompareStr goes through a widestring manager and raises
  ENoWideStringSupport without one. Nothing here needs it under pxx, where the
  Wide names ARE the byte ones. The FPC run agrees, 15/15.) }

uses sysutils, math, classes;

var
  total, okc: Integer;

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

  writeln('total ok ', okc, ' / ', total);
end.
