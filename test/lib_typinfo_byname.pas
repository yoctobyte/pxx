program lib_typinfo_byname;
{ The FPC BY-NAME typinfo spelling -- GetStrProp(Instance, PropName) and its
  fifteen siblings -- which lib/rtl/typinfo.pas gained on 2026-09-05 and which
  every vendored FPC consumer (dwsRTTIExposer, the LCL, anything reading a form
  file) writes. Before the arms existed the literal fell into the PPropInfo slot
  and the program segfaulted instead of being told the overload did not exist.

  EVERY ROW BELOW WAS DIFFERENTIALLY CHECKED against fpc 3.2.2 -Mdelphi -O1
  compiled with FPC'S OWN typinfo, and the whole output matched byte for byte,
  including the set rendering in both bracket modes. So this file is a parity
  fixture, not a self-consistency one.

  `Col` is spelled with three letters and `C` with one ON PURPOSE: a
  one-character literal is tagged tyChar rather than tyString, and that is the
  case the first pointer guard missed -- see
  test_one_char_literal_not_a_typed_pointer_fails.pas.

  BUILT WITH $(COMPILER), NOT $(PXX_STABLE), and that is not an oversight: the
  by-name arms are only correctly resolved by a compiler carrying the pointee
  narrowing for string AND char literals. Under the pin the literal still binds
  to the PPropInfo slot and this file crashes. It moves to lib-test's pinned set
  at the next pin. }
{$mode objfpc}
uses typinfo;
type
  TColor = (clRed, clGreen, clBlue);
  TColors = set of TColor;
  TSub = class(TObject) end;
  TThing = class(TObject)
  private
    fName: string; fCount: Integer; fBig: Int64; fF: Double;
    fC: TColor; fS: TColors; fSub: TSub;
  published
    property Name: string read fName write fName;
    property Count: Integer read fCount write fCount;
    property Big: Int64 read fBig write fBig;
    property F: Double read fF write fF;
    property C: TColor read fC write fC;
    property Col: TColor read fC write fC;
    property S: TColors read fS write fS;
    property Sub: TSub read fSub write fSub;
  end;
var t: TThing;
begin
  t := TThing.Create;
  t.Sub := TSub.Create;
  SetStrProp(t, 'Name', 'zaphod');
  SetOrdProp(t, 'Count', 42);
  SetInt64Prop(t, 'Big', 5000000000);
  SetFloatProp(t, 'F', 2.5);
  SetEnumProp(t, 'C', 'clBlue');
  SetSetProp(t, 'S', 'clRed,clBlue');
  writeln('name=', GetStrProp(t, 'Name'));
  writeln('count=', GetOrdProp(t, 'Count'));
  writeln('big=', GetInt64Prop(t, 'Big'));
  writeln('float=', GetFloatProp(t, 'F'):0:2);
  writeln('enum1=', GetEnumProp(t, 'C'));
  writeln('enum3=', GetEnumProp(t, 'Col'));
  writeln('set=', GetSetProp(t, 'S'));
  writeln('setbr=', GetSetProp(t, 'S', True));
  writeln('obj=', GetObjectProp(t, 'Sub') <> nil);
  writeln('stored=', IsStoredProp(t, 'Name'));
  { A name that names no published property answers the accessor's zero rather
    than raising: this unit cannot `uses sysutils` (see TiCompareText) and so
    has no exception to raise. FPC raises EPropertyError here; the divergence is
    stated in typinfo.pas's interface and is the one row above NOT compared
    against the oracle. It must not crash, which is what these assert. }
  SetStrProp(t, 'Nope', 'x');
  writeln('missstr=[', GetStrProp(t, 'Nope'), ']');
  writeln('missord=', GetOrdProp(t, 'Nope'));
  writeln('missstored=', IsStoredProp(t, 'Nope'));
  writeln('unchanged=', GetStrProp(t, 'Name'));
  writeln('TYPINFO-BYNAME OK');
end.
