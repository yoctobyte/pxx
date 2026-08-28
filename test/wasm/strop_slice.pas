program StrOpSlice;
{ Managed-string CONCATENATION and COMPARISON — the RTL-call half of Phase 8.

  Neither is an instruction on any target: `a + b` is PXXStrConcat and the six
  comparisons are PXXStrEq / PXXStrCmp3. Getting them wrong on a pointer-shaped
  type produces a valid module that answers a different question — `a = b` as
  an i32.eq of two handles asks "the same buffer" where Pascal asked "the same
  characters", and it is RIGHT about half the time, which is worse than always
  wrong. Ordered comparison is the one with history: it reached no cross
  backend for a long while, so `'zzz' < 'aaa'` answered by ALLOCATION ORDER on
  four targets at once. Both are here.

  Operand shapes matter as much as the operators, because each reaches its
  (length, characters) pair differently: a handle carries its length below
  itself, a frozen buffer carries it inline at +0, and a Char carries nothing
  at all and has to be spilled to memory before anything can point at it. A
  Char on the LEFT and on the RIGHT are separate cases here because they use
  different halves of the scratch.

  What is NOT here is the leak assertion. An operand that owned its reference —
  a call result, a nested concat — must be released after the RTL call, and a
  leak changes no output at all, so it needs a heap observable rather than a
  diff. It lives in check_strop.sh and runs against wasm ALONE, because the
  native build is not a usable oracle for it (see the note at the end). }

var
  s, t, u: string;
  c: Char;
  fz: string[15];
  i: Integer;

function Make(n: Integer): string;
begin
  if n = 1 then Make := 'one' else Make := 'many';
end;

begin
  s := 'ab';
  t := 'cd';
  c := 'X';
  fz := 'frz';

  writeln(s + t);
  writeln(s + 'lit');
  writeln('lit' + s);
  writeln(s + c);
  writeln(c + s);
  writeln(s + fz);
  writeln(fz + s);
  writeln(Make(1) + Make(2));

  u := s + t + 'z';
  writeln(u, '|', Length(u));

  { NESTING, and specifically nesting with a Char on BOTH levels. A Char is a
    value, so it has to be spilled to memory before an RTL routine can point at
    it, and the first version of this reserved ONE area per body: the inner
    Char landed on the outer Char's address and `a + (b + s)` printed `BBS` for
    `ABS`, a valid module with the wrong answer. Written with explicit
    parentheses because Pascal's `+` is left-associative and the natural
    spelling nests on the left, where the clash does not happen — the shape
    that fails is the one nobody writes by accident. }
  writeln(c + ('Y' + s));
  writeln((c + s) + 'Y');
  writeln(c + (s + 'Y'));
  writeln((c + 'Y') + (c + 'Y'));

  { The empty string is the NIL handle: length 0 and a pointer nothing may
    dereference, on both sides of both routines. }
  u := '';
  writeln('[', u + s, ']', '[', s + u, ']', '[', u + u, ']');

  writeln(s = 'ab', ' ', s = 'zz', ' ', s <> t, ' ', s <> 'ab');
  writeln('aaa' < 'bbb', ' ', 'zzz' < 'aaa', ' ', s <= s, ' ', t >= s);
  writeln('ab' < 'abc', ' ', 'abc' > 'ab');
  writeln(Make(1) = 'one', ' ', Make(2) = 'one');
  writeln('' = '', ' ', s = '', ' ', '' < s);

  { The owned-temporary leak assertion is NOT here. It lives in
    check_strop.sh, run against wasm alone, because the native build is not a
    usable oracle for it: x86-64 leaks a managed-string operand on every string
    COMPARISON — 40 bytes per evaluation of `f(x) = 'lit'`, measured, absent on
    all four cross backends and absent under FPC. Filed as
    bug-a-a-string-function-result-in-a-comparison-leaks-on-x86-64. Diffing a
    leak figure against a build with an open leak in it would assert the bug. }
  u := s + t;
  writeln(u, '|', u = 'abcd', '|', Length(u));
  writeln(u);
end.
