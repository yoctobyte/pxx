{ `type helper for T` — FPC's alternate spelling of `record helper for T`
  (feature-pascal-type-helpers v3 slice). The `record`/`type` keyword is cosmetic;
  both build the same helper-marked entry. Instance method (Self by reference) and a
  static both dispatch through the existing helper machinery. FPC needs
  {$modeswitch typehelpers} for the same code; pxx accepts it by default. Prints "42 0". }
program test_type_helper_for_spelling;
{$mode objfpc}
type
  TIntHelper = type helper for LongInt
    function Dbl: LongInt;
    class function Zero: LongInt; static;
  end;
function TIntHelper.Dbl: LongInt; begin Dbl := Self * 2; end;
class function TIntHelper.Zero: LongInt; begin Zero := 0; end;
var x: LongInt;
begin
  x := 21;
  writeln(x.Dbl, ' ', x.Zero);
end.
