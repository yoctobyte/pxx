program test_conversion_operator_no_capacity_match_is_refused;
{$mode delphi}
{ A record cast to a frozen-string type that NO conversion operator produces is
  a diagnostic, not a reinterpret.

  This file declares one Explicit operator returning ShortString and casts to
  String[40]. Capacity does not match, so no Explicit operator serves the
  destination; there is no Implicit operator to retry against; and a raw
  record-to-string cast would write whatever the record's first byte holds as a
  LENGTH BYTE and segfault in WriteLn. That segfault is dated -- it is why the
  generic-Explicit fallback existed at all.

  fpc 3.2.2 refuses the same program:
    Illegal type conversion: "TTest" to "TS40"
  so this is agreement, not a pxx-only restriction. Its sibling
  test_conversion_operator_result_capacity_is_part_of_its_identity.pas is the
  same shape WITH an Implicit operator declared, and there the cast succeeds
  through the retry -- the pair is what separates "the retry works" from "the
  refusal swallows everything".
  bug-p-an-explicit-cast-with-no-capacity-match-falls-back-to-the-wrong-conversion-operator }
type
  TS40 = String[40];

  TTest = record
    class operator Explicit(const aArg: TTest): ShortString;
  end;

class operator TTest.Explicit(const aArg: TTest): ShortString;
begin WriteLn('toSS'); Result := 'c'; end;

var
  s40: TS40;
  t: TTest;
begin
  s40 := TS40(t);
  WriteLn('got ', s40);
end.
