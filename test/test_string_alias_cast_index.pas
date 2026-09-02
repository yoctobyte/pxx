program test_string_alias_cast_index;
{ `TAlias(s)[i]`, read and written, for every string flavour a named alias can
  have — and the value-shape controls that must NOT change.

  The bug: the cast arms for a STRING-typed alias returned the operand and
  EXITED, leaving the `[i]` standing in the token stream. Not misparsed —
  DROPPED — so whatever came next swallowed it and the expression silently
  answered the WHOLE STRING. One cause, three faces by position: a silent wrong
  value in an assignment, `cannot assign AnsiString to Char` in a typed one, and
  `expected ')' before '['` in argument position. The frozen-string flavour
  failed differently (it fell into the pointer fall-through and read its index
  through the PChar adapter) and was found by grepping for the sibling rather
  than by a second report.

  THE ROWS THAT PIN THE OTHER DIRECTION are `value overload` and `value concat`,
  and they were chosen by RUNNING the control rather than by reading the arm's
  own comment. The cast must stay a value-level no-op; a fix that let it become a
  pointer reinterpret passes every index row above. With the no-op arm disabled
  and the compiler rebuilt, `F(tbtstring('ab'))` binds the POINTER overload and
  answers `ptr`, and `tbtstring('x') + 'y'` prints `1088` -- the pointer as a
  number. The `Pos` and `Length` rows do NOT discriminate: they were green under
  that same broken build, which is why they are here as coverage and are not
  claimed as the control.

  Every expectation below is fpc 3.2.2's answer on this same source.
  bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index }
type
  TAnsi  = AnsiString;
  tbtstring = AnsiString;   { Pascal Script's spelling, the original report }
  TShort = String[20];
  TNamed = ShortString;
  TWide  = WideString;
  TUni   = UnicodeString;
  TI     = Integer;
  TC     = Char;
var
  ok, total: Integer;

procedure Chk(name: AnsiString; cond: Boolean);
begin
  Inc(total);
  if cond then begin Inc(ok); WriteLn('ok   ', name); end
  else WriteLn('FAIL ', name);
end;

procedure TakeC(name: AnsiString; c, want: Char);
begin
  Chk(name, c = want);
end;

{ The overload pair the `value overload` control needs: a string alias cast must
  bind the AnsiString arm. Under a pointer reinterpret it binds the Pointer one. }
function F(const a: AnsiString): AnsiString; overload;
begin F := 'str:' + a; end;
function F(p: Pointer): AnsiString; overload;
begin F := 'ptr'; end;

var
  s, t: AnsiString;
  sh: TShort;
  ns: ShortString;
  w: WideString;
  u: UnicodeString;
  i: Integer;
  c: Char;
  b: Boolean;
begin
  ok := 0; total := 0;

  { --- read, all four flavours --- }
  s := 'hello';
  Chk('ansi read',        TAnsi(s)[1] = 'h');
  Chk('ansi read mid',    tbtstring(s)[4] = 'l');
  sh := 'world';
  Chk('String[N] read',   TShort(sh)[1] = 'w');
  ns := 'world';
  Chk('ShortString read', TNamed(ns)[2] = 'o');
  w := 'hello';
  Chk('WideString read',  TWide(w)[2] = 'e');
  u := 'world';
  Chk('Unicode read',     TUni(u)[3] = 'r');

  { --- the three FACES of the one cause: a Char target, a comparison, and
        argument position. Each was a different error message. --- }
  c := TAnsi(s)[1];
  Chk('char target',      c = 'h');
  b := TAnsi(s)[1] = 'h';
  Chk('comparison',       b);
  TakeC('argument position', TAnsi(s)[5], 'o');

  { --- write, all four flavours --- }
  s := 'hello';
  TAnsi(s)[2] := 'X';
  Chk('ansi store',       s = 'hXllo');
  sh := 'world';
  TShort(sh)[1] := 'W';
  Chk('String[N] store',  sh = 'World');
  ns := 'world';
  TNamed(ns)[2] := 'O';
  Chk('ShortString store', ns = 'wOrld');
  w := 'hello';
  TWide(w)[1] := 'H';
  Chk('WideString store', w = 'Hello');

  { --- THE CONTROLS. A cast to a string alias is a VALUE-LEVEL NO-OP, not a
        pointer reinterpret; tagging it tyPointer once made Pos() miss every
        string overload, which is why the arm exits early when no `[` follows. }
  t := tbtstring(' ');
  Chk('value no-op',      (t = ' ') and (Length(t) = 1));
  s := 'hello';
  Chk('value in Pos',     Pos(tbtstring('ll'), s) = 3);
  Chk('value overload',   F(tbtstring('ab')) = 'str:ab');
  Chk('value concat',     tbtstring('x') + 'y' = 'xy');
  sh := 'world';
  Chk('frozen value',     (Length(TShort(sh)) = 5) and (Pos(TShort('rl'), sh) = 3));

  { --- and the two aliases that go through the SAME arm and were already
        right: they must stay right. --- }
  i := 0; TI(i) := 5;
  Chk('int alias whole',  i = 5);
  c := 'a'; TC(c) := 'q';
  Chk('char alias whole', c = 'q');
  s := 'aaa'; TAnsi(s) := 'zzz';
  Chk('ansi alias whole', (s = 'zzz') and (Length(s) = 3));

  WriteLn('total ok ', ok, ' / ', total);
end.
