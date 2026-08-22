program test_char_variant_converts_as_text;
{ A one-character string LITERAL is boxed as VT_CHAR and a string VARIABLE as
  VT_STRING, so the same value converted two ways: `v := '7'; i := v` gave 55
  (the character code) while `s := '7'; v := s; i := v` gave 7. FPC has no char
  variant at all — `v := c` with c: Char reports VarType 256, varString — so it
  answers 7 for both. Whatever the dialect decides about a char variant, two
  spellings of one value must agree.
  bug-a-a-char-variant-converts-to-its-ordinal-not-its-text }
uses Variants, SysUtils;
var v: Variant; s: string; c: Char; i: Integer; l: Int64; d: Double; ok: Integer;
begin
  ok := 0;
  v := '7';            i := v; if i = 7  then Inc(ok);   { literal }
  s := '7'; v := s;    i := v; if i = 7  then Inc(ok);   { via a variable }
  c := '7'; v := c;    i := v; if i = 7  then Inc(ok);   { via a real Char }
  v := '77';           i := v; if i = 77 then Inc(ok);   { two chars — always worked }
  v := '7';            l := v; if l = 7  then Inc(ok);
  v := '7';            d := v; if (d > 6.9) and (d < 7.1) then Inc(ok);
  { a non-numeric character raises, exactly as a non-numeric string does }
  v := 'a';
  try
    i := v;
    WriteLn('no raise ', i);
  except
    on E: Exception do Inc(ok);
  end;
  { and it reads as text, not as an ordinal }
  v := '7';            if VarIsStr(v) then Inc(ok);
  c := 'q'; v := c;    if VarIsStr(v) then Inc(ok);
  v := '7'; s := v;    if (s = '7') and (Length(s) = 1) then Inc(ok);
  WriteLn('total ok ', ok, ' / 10');
end.
