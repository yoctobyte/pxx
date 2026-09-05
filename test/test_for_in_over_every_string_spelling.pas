program test_for_in_over_every_string_spelling;
{ `for ch in <a string>` was implemented PER SPELLING, and the spellings that
  were missing outnumbered the ones that were there.

  Two independent gaps, both asserted below:

  1. THE SOURCE. A bare string VARIABLE had an arm and a string LITERAL had its
     own arm keyed on the tkString TOKEN; a named string CONSTANT is a tkIdent
     and matched neither, so it fell past every bare-name arm to the general
     container-expression path at the bottom -- which knows about classes with
     GetEnumerator and about arrays, and nothing about strings. `const S =
     'abc'; for ch in S` was refused with "not a generator, enum type, or
     iterable variable" while `v := 'abc'; for ch in v` compiled in the same
     program. A concatenation and a string-returning CALL were refused for the
     same reason. All three now share the variable form's lowering rather than
     growing a fourth arm.

  2. THE KIND. `isString` was spelled `(tk = tyString) or (tk = tyAnsiString)`
     at three sites, so a ShortString or a `string[N]` container was "not a
     string or array" -- while two arms EARLIER IN THE SAME FUNCTION already
     asked TypeIsFrozenString. TypeIsAnyString exists precisely for this and its
     header says so: a guard meaning "is this a string" must not enumerate
     kinds, because the frozen-prefix work keeps changing the set.

  Every row here is byte-compared against FPC 3.2.2. The empty-string row is the
  one that says the loop is bounded by Length and not by a terminator; the
  `string[N]` row is the one that says a frozen container reads its own prefix
  width rather than the generic one.

  Fails on pin v403 (214500da2) at the FIRST row -- it cannot compile the file. }

const S = 'abc';
type TS4 = string[4];
type TRec = record f: shortstring; end;

function Mk: string; begin Mk := 'fn'; end;

var ch: Char; v: string; sh: shortstring; fx: TS4; r: TRec; n: Integer;
begin
  v := 'xy'; sh := 'pq'; fx := 'rst'; r.f := 'uv';
  Write('const  '); for ch in S     do Write(ch); WriteLn;
  Write('var    '); for ch in v     do Write(ch); WriteLn;
  Write('lit    '); for ch in 'lm'  do Write(ch); WriteLn;
  Write('concat '); for ch in v + S do Write(ch); WriteLn;
  Write('call   '); for ch in Mk    do Write(ch); WriteLn;
  Write('short  '); for ch in sh    do Write(ch); WriteLn;
  Write('fixed  '); for ch in fx    do Write(ch); WriteLn;
  Write('field  '); for ch in r.f   do Write(ch); WriteLn;
  n := 0;
  for ch in '' do Inc(n);
  WriteLn('empty  ', n);
end.
