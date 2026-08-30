program test_widestring_lowering;
{ feature-unicodestring-model step 7c -- the LOWERING.

  7b made the compiler believe UTF-16 while the runtime still stored UTF-8, so
  a wide program was silently wrong: Length halved a byte count that was never
  doubled, and indexing stepped two bytes through UTF-8. This test pins the
  lowering that closed that gap -- a literal reaching a wide destination is
  transcoded, a wide concat goes to the wide runtime, and Write transcodes
  back -- across every entity that can carry the width.

  ALL SIX CARRIERS, deliberately. A variable, a type alias, a record field, a
  UnicodeString spelling, an array element and a function RESULT each hold the
  element width in a different slot (Syms[].ElemType, AliasStrElemTk,
  UFldStrElemTk, SymStrElemTk, ProcRetStrElemTk), and each was written before
  anything read it. The record field is here because it is the one that was
  WRONG when the first reader arrived: symtab.inc hardwired Ord(tyChar) under a
  comment explaining why that was safe, and it was, until 7b landed.

  The .expected file is an ORACLE: FPC 3.2.2 produces it byte for byte. Kept to
  ASCII on purpose -- a non-ASCII literal would compare pxx's UTF-8 source
  reading against FPC's DefaultSystemCodePage one, which is a codepage
  question and not a lowering question. }
{$define PXX_WIDE_PAYLOAD}
type
  TWAlias = WideString;
  TRecW   = record w: WideString; end;
var
  w: WideString; a: TWAlias; r: TRecW; u: UnicodeString;
  arr: array[0..1] of WideString;
  s: AnsiString;
  i: Integer;

function F: WideString;
begin
  F := 'result';
end;

begin
  w := 'abcd';  a := 'abcd';  r.w := 'abcd';  u := 'abcd';
  { Length counts CODE UNITS, not bytes, and indexing steps one unit. }
  writeln('var   len=', Length(w),   ' [2]=', w[2],   ' out=', w);
  writeln('alias len=', Length(a),   ' [2]=', a[2],   ' out=', a);
  writeln('field len=', Length(r.w), ' [2]=', r.w[2], ' out=', r.w);
  writeln('ucode len=', Length(u),   ' [2]=', u[2],   ' out=', u);
  arr[0] := 'xy'; arr[1] := 'zw';
  writeln('array len=', Length(arr[0]), ' out=', arr[0], arr[1]);
  writeln('func  len=', Length(F), ' out=', F);
  { Concat: wide+wide, and the MIXED forms in both orders -- a narrow operand
    is widened rather than interleaved, so `s + w` and `w + s` agree. }
  writeln('cat   len=', Length(w + a), ' out=', w + a);
  s := 'NS';
  writeln('mixL  len=', Length(w + s), ' out=', w + s);
  writeln('mixR  len=', Length(s + w), ' out=', s + w);
  writeln('mixLit len=', Length(w + '!!'), ' out=', w + '!!');
  { Round trip back to a byte string, and the reverse. }
  s := w;
  writeln('narrow len=', Length(s), ' out=', s);
  w := s;
  writeln('rewide len=', Length(w), ' out=', w);
  { Every unit, read one at a time. }
  w := 'abc';
  write('units:');
  for i := 1 to Length(w) do write(' ', Ord(w[i]));
  writeln;
  { The empty string is the nil handle in both widths. }
  w := '';
  writeln('empty len=', Length(w), ' out=[', w, ']');
end.
