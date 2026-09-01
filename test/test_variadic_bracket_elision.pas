program test_variadic_bracket_elision;
{ Variadic bracket-elision: `f(a, b, c)` where f's last parameter is
  `array of const` is `f([a, b, c])`. Phase 1 of feature-writeln-as-library.

  THE LOAD-BEARING ROWS ARE THE `same-as-brackets` PAIRS. Every other row
  could be satisfied by an elision that builds a subtly different
  AN_VARREC_ARRAY -- a wrong element tag, a dropped element -- and would still
  print something. Comparing the elided call against the EXPLICITLY BRACKETED
  call of the same routine is what pins the two spellings to one node, which
  is the whole reason MakeVarRecArrayFromArgs exists.

  The overload rows are the ambiguity rule: the elision is a FALLBACK, so an
  exact non-variadic overload must still win. That row fails if the elision is
  ever moved ahead of overload resolution instead of behind its failure. }
uses sysutils;

var bad: Integer;

function Desc(const a: array of const): string;
{ Element TAGS, not values -- the tag is what the elision could get wrong. }
var i: Integer; s: string;
begin
  s := '';
  for i := 0 to High(a) do
  begin
    if i > 0 then s := s + ',';
    case a[i].VType of
      0:  s := s + 'i';
      1:  s := s + 'b';
      2:  s := s + 'c';
      3:  s := s + 'f';
      11: s := s + 's';
      16: s := s + 'I';
    else  s := s + '?';
    end;
  end;
  Desc := s;
end;

function DescAt(lvl: Integer; const a: array of const): string;
{ fixed parameters BEFORE the variadic tail -- the elision must splice at the
  right slot, not swallow the whole argument list. }
begin
  DescAt := IntToStr(lvl) + ':' + Desc(a);
end;

function Fwd(const a: array of const): string;
{ `array of const` PASS-THROUGH. This must stay a forward of the same vector
  and must never become Desc([a]) -- the one way elision could break code that
  compiles today. It is safe because the call RESOLVES, so the elision (which
  runs only after resolution has failed) is never reached; the row is here to
  fail loudly if that placement ever changes. }
begin
  Fwd := Desc(a);
end;

function Pick(const s: string): string; overload;
begin Pick := 'exact'; end;
function Pick(const a: array of const): string; overload;
begin Pick := 'variadic:' + Desc(a); end;

procedure Chk(const tag, got, want: string);
begin
  if got = want then WriteLn(tag, '=ok')
  else begin WriteLn(tag, '=FAIL got[', got, '] want[', want, ']'); Inc(bad); end;
end;

var d: Double;
begin
  bad := 0;
  d := 1.5;

  Chk('many',       Desc('xy', 1, True, d), 's,i,b,f');
  Chk('one',        Desc('only'),           's');
  Chk('none',       Desc(),                 '');
  Chk('after-fixed', DescAt(7, 'ab', 2),    '7:s,i');
  Chk('fixed-only',  DescAt(7),             '7:');

  { A one-character literal is a Char, not a one-character string: the
    PARAMETER decides, and an `array of const` slot imposes nothing. Asserted
    rather than avoided -- it is the elision's one visible surprise. }
  Chk('one-char-is-vtChar', Desc('x', 1), 'c,i');

  Chk('same-as-brackets-A', Desc('xy', 1, True, d), Desc(['xy', 1, True, d]));
  Chk('same-as-brackets-B', DescAt(7, 'ab', 2),     DescAt(7, ['ab', 2]));
  Chk('same-as-brackets-C', Desc(),                 Desc([]));
  Chk('brackets-still-work', Desc(['xy', 1]),       's,i');

  Chk('passthrough-not-wrapped', Fwd(['xy', 1]),    's,i');

  Chk('overload-exact-wins',        Pick('one string'), 'exact');
  Chk('overload-variadic-fallback', Pick('ab', 1),      'variadic:s,i');
  Chk('overload-explicit-brackets', Pick(['ab', 1]),    'variadic:s,i');

  if bad = 0 then WriteLn('ELISION OK') else WriteLn('FAILURES: ', bad);
end.
