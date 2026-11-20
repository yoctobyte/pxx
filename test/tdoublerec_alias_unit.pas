unit tdoublerec_alias_unit;
{ The shape of FPC's own x86_64/cpuinfo.pas: TDoubleRec named in a UNIT whose
  uses cannot supply it, through an ALIAS, and cast to with a method call
  (nadd.pas's `bestrealrec(v).SpecialType`). feature-b-rtl-has-no-tdoublerec }
{$mode objfpc}
interface
type
  bestreal = double;
  bestrealrec = TDoubleRec;
function IsFiniteNonZero(v: bestreal): Boolean;
function MantissaOf(v: bestreal): QWord;
implementation
function IsFiniteNonZero(v: bestreal): Boolean;
begin
  Result := bestrealrec(v).SpecialType in [fsPositive, fsNegative];
end;
function MantissaOf(v: bestreal): QWord;
begin
  Result := bestrealrec(v).Mantissa;
end;
end.
