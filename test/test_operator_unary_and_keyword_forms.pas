{ Unit-scope operator overloading was missing three things at once, all of them
  visible in FPC's own compiler/constexp.pas, which declares 22 operators on one
  record:

    1. a UNARY overload -- `operator - (const a:T):T` -- was routed to the
       binary arity check and refused outright ("binary operator must take
       exactly two parameters"). The same symbol carrying BOTH arities is the
       normal case, not an edge one, so arity is now what tells the two entries
       apart, in the table (FindOpOverloadUnary) and in the binary lookup's
       aggregate fallback (which would otherwise have answered `a - b` with the
       one-parameter proc).
    2. the KEYWORD-spelled operators -- and, or, xor, shl, shr, not -- were not
       in the accepted-symbol list at all, so `operator and (const a,b:T):T` was
       a syntax error while `operator + (const a,b:T):T` was fine.
    3. an AN_NEG / AN_NOT node had no record identity, so `(-a) + b` could not
       find the `+` overload and `var c := -a` would have been sized REC_NONE.

  Unary `+` is deliberately absent: ParseSimpleExpr eats a leading plus as an
  identity before a node exists, so there is nothing to dispatch on.

  Every row is `fpc -O- -Mobjfpc` 3.2.2's.
  feature-p-fpc-global-operator-overload-declarations }
program test_operator_unary_and_keyword_forms;

type
  TCe = record v: Int64; end;

{ the pair that shares one symbol and differs only in arity -- constexp.pas:65,66 }
operator - (const a, b: TCe): TCe;
begin Result.v := a.v - b.v; end;
operator - (const a: TCe): TCe;
begin Result.v := -a.v; end;

operator + (const a, b: TCe): TCe;
begin Result.v := a.v + b.v; end;
operator * (const a, b: TCe): TCe;
begin Result.v := a.v * b.v; end;

{ the keyword-spelled ones -- constexp.pas:78-82 }
operator and (const a, b: TCe): TCe;
begin Result.v := a.v and b.v; end;
operator or  (const a, b: TCe): TCe;
begin Result.v := a.v or b.v; end;
operator xor (const a, b: TCe): TCe;
begin Result.v := a.v xor b.v; end;
operator shl (const a, b: TCe): TCe;
begin Result.v := a.v shl b.v; end;
operator shr (const a, b: TCe): TCe;
begin Result.v := a.v shr b.v; end;
operator not (const a: TCe): TCe;
begin Result.v := not a.v; end;

operator = (const a, b: TCe): Boolean;
begin Result := a.v = b.v; end;

var
  x, y, z: TCe;

begin
  x.v := 12; y.v := 10;

  { arity picks between the two `-` entries }
  z := x - y;  writeln(z.v);
  z := -x;     writeln(z.v);

  { a unary result feeding a binary operator -- needs the NEG node's record }
  z := (-x) + y;  writeln(z.v);
  z := -(x - y);  writeln(z.v);
  z := -(-x);     writeln(z.v);

  { keyword operators, binary }
  z := x and y;  writeln(z.v);
  z := x or y;   writeln(z.v);
  z := x xor y;  writeln(z.v);
  y.v := 2;
  z := x shl y;  writeln(z.v);
  z := x shr y;  writeln(z.v);

  { keyword operator, unary, and its result feeding another overload }
  y.v := 10;
  z := not x;        writeln(z.v);
  z := (not x) + y;  writeln(z.v);
  z := not (not x);  writeln(z.v);

  { a unary result compared through an overloaded `=` }
  z := -x;
  writeln(z = -x, ' ', z = x);
end.
