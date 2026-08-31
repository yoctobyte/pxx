program member_on_array_element_string;
{ Refusal fixture for bug-p-a-member-on-an-array-element-silently-reads-the-
  elements-own-bytes. There is no helper in scope, so this member cannot exist;
  before the fix it compiled and printed a pointer as an integer. }
var a: array[0..1] of AnsiString;
begin
  a[0] := 'z';
  WriteLn(a[0].NoSuchMember);
end.
