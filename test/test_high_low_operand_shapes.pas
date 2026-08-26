{ What `High`/`Low` accept as an operand, and what base they answer in.

  Both arms opened with `if CurTok.Kind <> tkIdent then Error(...)`, so every
  operand that does not START with a name was refused: a literal, a
  parenthesised expression, and — less obviously — a name with an OPERATOR after
  it, which stopped the lvalue parser at the name and then died on the operator.
  A proc NAME escaped only because a name starts with an identifier.

  The operand is dispatched by SHAPE now (HighLowOperandIsExpr), not by its
  first token. `High(3)` still gets its clear error rather than reaching the
  runtime Length tail and producing garbage — that is the point of dispatching
  rather than widening.

  THREE BASES, and "it starts with a quote" tells you nothing:

    'abc'      a string CONSTANT is an array-of-CHAR constant   0 .. len-1
    ('ab')     …and the parens do not change that — ask the NODE, not the token
    'ab' + s   a MANAGED string expression                      1 .. Length
    sh         a FROZEN string variable                         0 .. capacity

  Every row below is fpc 3.2.2's own answer. The array/ordinal rows are here
  because the dispatch change moves the decision for all of them, not only for
  the new shapes.

  KNOWN DIVERGENCE, deliberately not asserted here: a concatenation with a
  SHORTSTRING operand (`sh + 'x'`) is a shortstring EXPRESSION in fpc and
  answers 0 .. 255, the default capacity; pxx answers 1 .. Length. pxx does not
  model a shortstring expression's capacity at all — `SizeOf(sh)` is 8 here and
  11 in fpc — so matching that row means changing the string model, not this
  intrinsic. `'ab' + 'cd'` is the same divergence and fpc is not even
  self-consistent about it: objfpc says 0/255, Delphi mode says 1/4, which is
  pxx's answer. Recorded in devdocs/dev/pascal-dialect-divergences.md.

  bug-p-every-compile-time-intrinsic-hand-rolls-its-own-operand-parser }
program test_high_low_operand_shapes;

type
  TA = array[5..9] of Integer;
  TD = array of Integer;
  TE = (eA, eB, eC);
  TR = record buf: array[0..7] of Byte; end;
  PA = ^TA;

var
  a: TA;
  d: TD;
  r: TR;
  p: PA;
  i: Integer;
  m: array[0..2, 0..3] of Integer;
  s: AnsiString;
  sh: string[10];

function MakeArr: TD;
begin
  SetLength(MakeArr, 4);
end;

begin
  SetLength(d, 3);
  p := @a;
  s := 'qxy';
  sh := 'zz';

  { the shapes that used to be refused outright }
  WriteLn('lit    : ', Low('abc'),     ' ', High('abc'));
  WriteLn('paren  : ', Low(('ab')),    ' ', High(('ab')));
  WriteLn('ansiexp: ', Low('ab' + s),  ' ', High('ab' + s));
  WriteLn('ansiop : ', Low(s + 'x'),   ' ', High(s + 'x'));

  { …and the bases for a plain string variable of each kind }
  WriteLn('ansivar: ', Low(s),  ' ', High(s));
  WriteLn('frozvar: ', Low(sh), ' ', High(sh));

  { every shape that already worked, pinned because the dispatch moved }
  WriteLn('arrvar : ', Low(a), ' ', High(a));
  WriteLn('arrtype: ', Low(TA), ' ', High(TA));
  WriteLn('dyn    : ', Low(d), ' ', High(d));
  WriteLn('call   : ', Low(MakeArr), ' ', High(MakeArr));
  WriteLn('field  : ', Low(r.buf), ' ', High(r.buf));
  WriteLn('deref  : ', Low(p^), ' ', High(p^));
  WriteLn('nd     : ', Low(m), ' ', High(m));
  WriteLn('ordvar : ', Low(i), ' ', High(i));
  WriteLn('enum   : ', Ord(Low(TE)), ' ', Ord(High(TE)));
end.
