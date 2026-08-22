{ Indexing a string that has no addressable base.

  `(s)[3]` COMPILED CLEAN AND SEGFAULTED: the grouped-expression suffix loop
  built a raw AN_INDEX over the string, so it indexed the string HANDLE rather
  than a slot holding one. `(s + 'x')[3]` reached IR_UNSUPPORTED, and a bare
  literal `'hello'[1]` was a syntax error — while a NAMED constant and a
  string-returning CALL both worked.

  The call-result arm already knew the answer (materialise into a temp and yield
  `(tmp := value, tmp[i])` via AN_COMMA); the grouped arm had its own, broken
  copy. One helper now, GenMakeStringValueIndex, used by both.
  bug-a-indexing-a-parenthesised-string-compiles-and-segfaults }
program test_indexing_a_string_value;

uses SysUtils;

const
  KLit = 'hello';

var
  s: AnsiString;
  i, n: Integer;

function Counted: AnsiString;
begin
  Inc(n);
  Counted := 'xyz';
end;

var
  a: array[0..3] of Integer;
begin
  s := 'abcd';

  { the crash: a grouped string variable }
  WriteLn('grp   ', (s)[2]);
  WriteLn('grp2  ', ((s))[3]);

  { the refusal: a grouped string EXPRESSION }
  WriteLn('expr  ', (s + 'ef')[5], (s + 'ef')[6]);
  WriteLn('call  ', (UpperCase(s))[1]);

  { the syntax error: a bare literal, with a constant, variable and computed
    index }
  WriteLn('lit   ', 'hello'[1], 'hello'[5]);
  for i := 1 to 5 do Write('hello'[i]);
  WriteLn;
  i := 1;
  WriteLn('lidx  ', 'hello'[i + 2]);

  { the value must be evaluated EXACTLY ONCE — the whole point of the temp }
  n := 0;
  WriteLn('once  ', (Counted)[2], ' ', n);

  { ...and the shapes that already worked must keep working }
  WriteLn('named ', KLit[1], KLit[5]);
  WriteLn('fncall', ' ', UpperCase(s)[1], UpperCase(s)[2]);
  s := 'abc';
  WriteLn('direct', ' ', s[1], s[3]);
  for i := 0 to 3 do a[i] := i * 2;
  WriteLn('arr   ', (a)[2], ' ', a[3]);
end.
