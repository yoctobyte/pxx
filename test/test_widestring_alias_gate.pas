program test_widestring_alias_gate;
{ feature-unicodestring-model step 7b.

  WideString/UnicodeString remain an ALIAS for the byte string by default, and
  become the wide ELEMENT WIDTH of the one managed-string kind only under
  {$define PXX_WIDE_PAYLOAD}. This test pins the DEFAULT direction, which is the
  one every existing program depends on.

  It is deliberately not a test of wideness: the payload is still UTF-8 and the
  lowering that would make it UTF-16 does not exist yet, so under the define
  Length answers in half-byte-counts rather than characters. Asserting that here
  would freeze a number the lowering is supposed to change. }
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
