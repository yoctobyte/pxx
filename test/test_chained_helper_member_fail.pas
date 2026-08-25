{ %FAIL-style negative: a member on the RESULT of a type-helper method.

  A helper method's return type resets the selector loop's record id to
  REC_NONE, and the loop kept going — so with a `type helper for string` in
  scope `s.Twice.Twice` printed 24929 (the two bytes of 'aa' as an Int32) and
  `s.Twice.IsEmpty` printed 24929 as well, the trailing member silently
  DROPPED. Two different members, one wrong number, no diagnostic.

  Chaining a real helper method now WORKS (test_type_helper_on_a_value pins
  `s.Twice.Twice` against FPC), so the member here is deliberately one that
  exists nowhere: the refusal has to survive the feature that made the valid
  spelling compile, or the silent read comes back for every typo.
  bug-p-a-member-on-a-computed-value-silently-reads-the-values-own-bytes }
{$mode objfpc}{$H+}{$modeswitch typehelpers}
program test_chained_helper_member_fail;
type
  TStrH = type helper for string
    function Twice: string;
  end;
function TStrH.Twice: string; begin Result := Self + Self; end;
var s: string;
begin
  s := 'a';
  writeln(s.Twice.NoSuchMember);
end.
