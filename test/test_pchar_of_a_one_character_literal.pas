program test_pchar_of_a_one_character_literal;
{ PChar('x') points at a NUL-terminated "x", as PChar('xy') points at "xy";
  it is not the character code 120 reinterpreted as an address.
  bug-a-pchar-of-a-one-character-literal-is-its-char-code }
{$mode objfpc}
const
  KC = 'k';
var
  p: PChar;
  pa: PAnsiChar;

procedure Show(const tag: string; q: PChar);
begin
  writeln(tag, ' ', PtrUInt(q) > 4096, ' ', q, ' ', q[0], ' ', Ord(q[1]));
end;

begin
  p := PChar('x');
  Show('lit', p);
  pa := PAnsiChar('z');
  Show('ansi', pa);
  Show('const', PChar(KC));
  Show('code', PChar(#65));
  Show('two', PChar('xy'));
  Show('arg', PChar('q'));
  writeln(PChar('m')^, ' ', PChar('n')[0]);
end.
