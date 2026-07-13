{ WideChar VALUES flowing into STRING contexts — the fpjson \uXXXX decoder shape.

  pxx's one string model is UTF-8 bytes and WideChar is a 2-byte ordinal, so before
  b319 a WideChar value reaching a string context was SILENTLY treated as a managed
  string POINTER: `U := widechar(U1)` retained the 16-bit value as an address
  (crash), `WideChar(u1)+WideChar(u2)` was integer ADDITION, and
  `UTF8Encode(WideChar(u))` passed the ordinal to the AnsiString parameter and
  corrupted memory. fpjson's JSONStringToString walked all three on any \uXXXX
  escape, which is why the fcl-json suite died in its very first test.

  Now the frontend marks `WideChar(x)` casts and converts at the string boundary
  through builtin helpers: assignment and string-parameter passing UTF-8-encode the
  code unit; WideChar+WideChar concatenation is surrogate-aware, so a high+low pair
  becomes ONE 4-byte code point exactly as FPC's UTF-16 -> UTF-8 conversion does
  (U+1F31F below); a lone surrogate yields the EMPTY string (FPC's conversion
  drops it). In ordinal contexts the cast keeps plain value-cast semantics
  (truncate to 16 bits). Verified against FPC. }
program test_widechar_to_utf8_b319;
{$mode objfpc}{$h+}

function Ident(const s: AnsiString): AnsiString;
begin
  Result := s;
end;

var
  s, t: AnsiString;
  u1, u2: Integer;
begin
  u1 := $F8;
  s := WideChar(u1);                        { assign: 2-byte UTF-8 }
  Writeln('1=', s, ' len=', Length(s));
  u1 := $D83C; u2 := $DF1F;
  t := WideChar(u1) + WideChar(u2);         { surrogate pair -> one 4-byte cp }
  Writeln('2=', t, ' len=', Length(t));
  s := 'x' + WideChar($E9);                 { widechar + string concat }
  Writeln('3=', s);
  s := WideChar(65) + 'bc';                 { ASCII stays 1 byte }
  Writeln('4=', s);
  Writeln('5=', Ident(WideChar($F8)));      { string parameter }
  Writeln('6=', Ident(WideChar($41) + WideChar($42)));  { two BMP units, no pair }
  s := WideChar($D800);                     { lone surrogate -> dropped (empty) }
  Writeln('7=', s);
  Writeln('8=', Ord(WideChar($1F231)) = $F231);  { ordinal context still truncates }
end.
