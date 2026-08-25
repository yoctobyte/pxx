{ %FAIL-style negative: a member on the RESULT of a type-helper method.

  A helper method's return type resets the selector loop's record id to
  REC_NONE, and the loop kept going — so with a `type helper for string` in
  scope `s.Twice.Twice` printed 24929 (the two bytes of 'aa' as an Int32) and
  `s.Twice.IsEmpty` printed 24929 as well, the trailing member silently
  DROPPED. Two different members, one wrong number, no diagnostic.

  Helper methods on a computed receiver are a real gap
  (feature-p-delphi-string-helpers) — FPC chains them fine. Refusing is the
  honest answer until they work; reading the value's own bytes is not.
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
  writeln(s.Twice.Twice);
end.
