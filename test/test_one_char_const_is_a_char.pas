{$mode objfpc}
{ A ONE-CHARACTER untyped constant is a CHAR, as FPC types it — not a string of
  length one.

  `const KC = 'z'` landed in the STRING const table, so a use built an
  AN_STR_LIT and every CHAR context read the string value's ADDRESS instead of
  the code point. Six consumers were wrong at once, which is why the fix is at
  the point of CLASSIFICATION rather than at any one of them
  (devdocs/dev/normalise-dont-special-case.md):

    Ord(KC)          4288109 (an address)   FPC 122
    c := KC         a byte of that address  FPC 'z'
    Chr(Ord(KC))     likewise                FPC 'z'
    KC in ['a','z'] FALSE                   FPC TRUE
    Ord(Succ(KC))    an address              FPC 123
    Length(KC)       the CODE POINT, and a SEGFAULT once C became a Char

  That last one was latent independently: Length of a Char VARIABLE answered
  120 for 'x' long before this ticket, while Length('y') on a literal answered
  1. Folded to 1 in the parser now.
  bug-pascal-ord-of-a-one-char-string-const-is-its-address

  Every expected value is FPC 3.2.2's on this same source. The STRING rows are
  here to prove the classification did not cost the string contexts a Char
  already converts into. }
program test_one_char_const_is_a_char;
const
  KC = 'z';
  Sep = '/';
  Empty = '';
  Multi = 'ab';
  Joined = Sep + 'x';
var
  c: Char;
  s: AnsiString;
  st: set of Char;
procedure TakeStr(const t: AnsiString); begin WriteLn('strparam ', t); end;
procedure TakeChar(ch: Char); begin WriteLn('chrparam ', ch); end;
begin
  { the char contexts that were wrong }
  WriteLn('ord      ', Ord(KC));
  c := KC;                 WriteLn('assign   ', c);
  WriteLn('chr      ', Chr(Ord(KC)));
  st := ['a', 'z'];       WriteLn('setin    ', KC in st);
  WriteLn('succ     ', Ord(Succ(KC)));
  WriteLn('pred     ', Ord(Pred(KC)));
  WriteLn('lenconst ', Length(KC));

  { Length of a Char VARIABLE and of a char LITERAL — the pre-existing half }
  c := 'x';
  WriteLn('lenvar   ', Length(c));
  WriteLn('lenlit   ', Length('y'));

  { the two that already worked — kept so a fix cannot trade them away }
  WriteLn('cmp      ', KC = 'z');
  case KC of
    'z': WriteLn('case     yes');
  else  WriteLn('case     no');
  end;

  { STRING contexts: a Char converts into all of them }
  s := Sep;                    WriteLn('tostr    ', s);
  s := Sep + 'home' + Sep;     WriteLn('concat   ', s);
  s := 'a' + Sep;              WriteLn('concat2  ', s);
  TakeStr(Sep);
  TakeChar(Sep);
  WriteLn('pos      ', Pos(Sep, '/a/b'));

  { and the constants that are NOT one character keep their string typing }
  WriteLn('empty    ', Length(Empty));
  WriteLn('multi    ', Length(Multi), ' ', Multi);
  WriteLn('joined   ', Joined, ' ', Length(Joined));
end.
