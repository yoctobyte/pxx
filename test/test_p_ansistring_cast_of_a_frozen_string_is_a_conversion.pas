program test_p_ansistring_cast_of_a_frozen_string_is_a_conversion;
{ AnsiString(<frozen string>) is a conversion, not a retag:
  PChar(AnsiString('hello')) pointed at the literal's length prefix, so
  Ord(p[0]) was 5, not 104. Asserted on Ord(p[0]) with literals of length >= 2,
  because lengths 0 and 1 agreed with fpc even while the bug was live. Every
  line matches fpc 3.2.2, including the overload choice.
  bug-p-pchar-of-an-ansistring-cast-of-a-literal-yields-one-garbage-byte }
{$mode objfpc}{$H+}
var p: PChar; s: AnsiString; sh: string[20]; t: ShortString;
procedure F(const a: ShortString); overload; begin WriteLn('F short ', a); end;
procedure F(const a: AnsiString); overload; begin WriteLn('F ansi ', a); end;
begin
  p := PChar(AnsiString('hello')); WriteLn(Ord(p[0]), ' [', p, ']');
  p := PChar(AnsiString('ab')); WriteLn(Ord(p[0]));
  p := PChar(AnsiString('')); WriteLn(Ord(p[0]));
  p := PChar(AnsiString('a')); WriteLn(Ord(p[0]));
  sh := 'frozen'; WriteLn('[', PChar(AnsiString(sh)), ']');
  t := 'short'; WriteLn('[', PChar(AnsiString(t)), ']');
  s := AnsiString('x') + AnsiString('yz'); WriteLn(s, ' ', Length(AnsiString('hello')));
  F(AnsiString('lit')); F(AnsiString(t));
  WriteLn(AnsiString('w') = 'w', ' ', Pos(AnsiString('l'), 'hello'));
end.
