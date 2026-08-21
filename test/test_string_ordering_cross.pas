program test_string_ordering_cross;
{$mode objfpc}{$H+}
{ Lexicographic ordering of managed strings, verified against FPC.

  The four cross backends had NO ordered-string arm: only `=` / `<>` were
  special-cased, so `<` `<=` `>` `>=` fell through to the ordinary integer
  compare and compared the two heap HANDLES. `'zzz' < 'aaa'` then answered by
  allocation order — a silent wrong value on i386, arm32, aarch64 and riscv32,
  and it stayed invisible because the obvious probe (`a := 'a'; b := 'b'`)
  allocates in the same order it compares and is therefore right by accident.
  Hence the deliberate cases below: reversed allocation order, prefixes, empty
  strings, and a byte above 127 (bytes compare UNSIGNED).
  bug-a-ordered-string-comparison-of-a-parameter-compares-handles-on-every-cross-target

  Separate from test_string_ordering.pas, which covers the same operators for a
  DIFFERENT defect (bug-string-ordering-comparison-constant, where the answer was
  a constant). That test would in fact have caught this one — it is simply never
  built for a cross target. Keeping both is deliberate: the older one is the
  native regression, this one is the shape a handle compare gets wrong. }

procedure T(const tag: string; const a, b: string);
begin
  Write(tag, ': ');
  if a < b then Write('lt ') else Write('.. ');
  if a <= b then Write('le ') else Write('.. ');
  if a > b then Write('gt ') else Write('.. ');
  if a >= b then Write('ge ') else Write('.. ');
  if a = b then Write('eq ') else Write('.. ');
  Writeln;
end;

var e, hi, x, y: string;
begin
  e := '';
  hi := #200'x';
  { allocate y FIRST so its handle is the LOWER address while its content is
    the LATER one — the case a handle compare gets backwards }
  y := 'zzz';
  x := 'aaa';
  T('aaa vs zzz ', 'aaa', 'zzz');
  T('zzz vs aaa ', 'zzz', 'aaa');
  T('abc vs abc ', 'abc', 'abc');
  T('ab  vs abc ', 'ab', 'abc');
  T('abc vs ab  ', 'abc', 'ab');
  T('empty vs a ', e, 'a');
  T('a vs empty ', 'a', e);
  T('empty x2   ', e, e);
  T('hi200 vs a ', hi, 'ax');
  T('A vs a     ', 'A', 'a');
  T('var x vs y ', x, y);
  T('var y vs x ', y, x);
end.
