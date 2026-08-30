program test_widestring_alias_gate;
{ feature-unicodestring-model step 7b.

  WideString/UnicodeString remain an ALIAS for the byte string by default, and
  become the wide ELEMENT WIDTH of the one managed-string kind only under
  {$define PXX_WIDE_PAYLOAD}. This test pins the DEFAULT direction, which is the
  one every existing program depends on.

  It is deliberately not a test of wideness: this file has no define, so the
  payload here is UTF-8 and Length counts its bytes. The wide side is pinned by
  test_widestring_lowering, which turns the define on and asserts the same six
  carriers against an FPC oracle; keeping the two apart is what makes a leak of
  the width into a DEFAULT build show up as this test failing rather than as a
  number quietly changing in that one. }
type
  TWAlias = WideString;
  TRecW   = record w: WideString; n: Integer; end;
var
  w: WideString; u: UnicodeString; a: TWAlias; r: TRecW;
begin
  w := 'abcd';
  u := 'abcd';
  a := 'abcd';
  r.w := 'abcd';
  r.n := 7;
  { All four must agree with the byte string they alias. }
  writeln('w=', w, ' len=', Length(w));
  writeln('u=', u, ' len=', Length(u));
  writeln('alias=', a, ' len=', Length(a));
  writeln('field=', r.w, ' len=', Length(r.w));
  { Indexing must step ONE byte, not two -- the symptom that appears first if
    the width leaks into a default build. }
  writeln('idx=', w[1], w[2], w[3], w[4]);
  { and the field after the string is not disturbed }
  writeln('next=', r.n);
end.
