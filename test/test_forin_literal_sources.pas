{$mode objfpc}
{ `for x in [...]` over a SET CONSTRUCTOR and `for c in 'literal'` over a string
  literal. Both were refused; `for c in s` over a string VARIABLE already
  worked, the usual two-spellings tell.

  The trap this file exists to pin down: **`[...]` here is a SET, not a list.**
  FPC iterates the MEMBERS in ordinal order, so `[5,1,3,2]` yields 1 2 3 5 — not
  source order. Implemented as list iteration it would silently produce a
  different ORDER, which is the expensive kind of wrong, so every row below is
  written in a deliberately unsorted order and asserts the sorted answer.

  A string literal is the opposite: SOURCE order, character by character, like
  the string-variable form.

  Two deliberate divergences, both lax-vs-strict and neither a wrong VALUE:

  FPC REFUSES a duplicate element (`[5,1,3,1,2]` is
  "duplicate set element"). PXX accepts it and yields the same set — a set is
  idempotent, so the restriction is historic rather than necessary, and the
  dialect stays lax by default (CLAUDE.md; FPC-parity strictness belongs behind
  a --strict-* flag).

  FPC also refuses `for c in 'x'` — a one-character literal IS a Char in Pascal
  and a Char has no enumerator. PXX reads it as the one-character string it is
  written as and iterates it, which is what anyone writing that line means.

  Every other row diffed against fpc -O1, and matches.
  bug-a-for-in-refuses-a-set-constructor-and-a-string-literal }
program test_forin_literal_sources;
type TE = (eA, eB, eC);
var
  i: Integer;
  c: Char;
  e: TE;
  s: string;
  n: Integer;
begin
  Write('ints  '); for i in [5, 1, 3, 2] do Write(i, ' '); WriteLn;
  Write('chars '); for c in ['z', 'a', 'm'] do Write(c, ' '); WriteLn;
  Write('enum  '); for e in [eC, eA] do Write(Ord(e), ' '); WriteLn;
  Write('range '); for i in [2..5] do Write(i, ' '); WriteLn;
  Write('mixed '); for i in [9, 1..3, 7] do Write(i, ' '); WriteLn;
  Write('empty '); n := 0; for i in [] do Inc(n); Write(n); WriteLn;
  Write('dup   '); for i in [5, 1, 3, 1, 2] do Write(i, ' '); WriteLn;

  Write('lit   '); for c in 'hello' do Write(c, '.'); WriteLn;
  Write('var   '); s := 'abc'; for c in s do Write(c, '-'); WriteLn;
  Write('one   '); for c in 'x' do Write(c, '!'); WriteLn;

  { the loop variable survives the loop and the body may branch/break }
  Write('break '); for i in [1..9] do begin if i > 3 then Break; Write(i, ' '); end; WriteLn;
  WriteLn('FORIN LITERAL SOURCES OK');
end.
