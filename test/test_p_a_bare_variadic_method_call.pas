{ Variadic BRACKET-ELISION at a call to the enclosing class's own method,
  spelled WITHOUT a receiver and in STATEMENT position: `Desc('a', 1);`
  against `Desc(const a: array of const)`.

  The bracketed spelling `Desc(['a', 1]);` of the same call, in the same
  program, ran correctly -- so this is not the elision feature being absent,
  it is the one call site that never reaches the tail where the elision is
  absorbed. The bare implicit-Self STATEMENT site hand-rolls its argument loop,
  and that loop swallowed to the `)`: each surplus expression became a separate
  AN_ARG, so the callee's open-array descriptor was whatever the SECOND one
  happened to be. `Length(a)` segfaulted, having compiled clean.

  STATEMENT AND EXPRESSION POSITION ARE BOTH ASSERTED, and that pairing is the
  point of the second half of this file. An earlier version of this header
  claimed the expression spelling "goes through a different parser arm that
  already had the tail". IT DID NOT -- it was the same hand-rolled loop with
  NONE of the five doors, and nobody had measured it: `Desc('a', 1)` there
  segfaulted exactly as the statement spelling did, and `Desc(['a', 1])`
  answered `n=0` because the bracket was still read as a set. Both loops are
  now one routine, and the rows below are what proves it: every statement row
  has an expression twin printing the same descriptor.
  bug-p-the-bare-self-call-in-expression-position-has-none-of-the-doors

  THE SINGLE-ELEMENT ROW IS NOT A WEAKER VERSION OF THE MULTI ONE -- it
  crashed by the other route. `Desc('a')` has an arity that MATCHES, so
  nothing is surplus and nothing was carved out; a scalar was simply handed to
  a slot that wants a vector. A file that only tested `Desc('a', 1)` would go
  green with that half still broken, which is why the absorbing tail is called
  unconditionally rather than only when a comma is in sight.

  EVERY ELIDED ROW IS PAIRED WITH ITS BRACKETED TWIN AND THE TWO MUST AGREE.
  The bracketed spelling always worked, so a row that only asserted the elided
  answer could be green against a wrong-but-stable descriptor; the pair names
  the door rather than the feature. The lengths asserted are ones the broken
  path could not produce -- it crashed -- but the VType columns are what would
  catch a descriptor that is merely mis-shaped rather than absent.

  The last four rows are the control for the change that fixed it: the loop is
  now BOUNDED at the declared parameter count, so an ordinary call, a defaulted
  one, and a parameterless one all have to keep working.

  bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works }
{$mode objfpc}
program test_p_a_bare_variadic_method_call;
type
  TC = class
    procedure Desc(const a: array of const);
    procedure Def(x: Integer = 3; y: Integer = 4);
    procedure NoArg;
    { the same two as FUNCTIONS, so the call can sit in an EXPRESSION -- a
      different parser arm, and the whole reason the second half exists. Two
      of them, because a length alone cannot tell a correct descriptor from a
      differently-wrong one: DescTag reads the LAST element's tag, which is
      the slot the old loop filled with whatever the second argument left. }
    function DescLen(const a: array of const): Integer;
    function DescTag(const a: array of const): Integer;
    function DefRet(x: Integer = 3; y: Integer = 4): Integer;
    procedure Work;
  end;

procedure TC.Desc(const a: array of const);
var i: Integer;
begin
  Write('n=', Length(a));
  for i := 0 to Length(a) - 1 do
    Write(' t', i, '=', a[i].VType);
  WriteLn;
end;

procedure TC.Def(x: Integer = 3; y: Integer = 4);
begin
  WriteLn('def ', x * 10 + y);
end;

procedure TC.NoArg;
begin
  WriteLn('noarg 99');
end;

function TC.DescLen(const a: array of const): Integer;
begin
  DescLen := Length(a);
end;

function TC.DescTag(const a: array of const): Integer;
begin
  DescTag := a[Length(a) - 1].VType;
end;

function TC.DefRet(x: Integer = 3; y: Integer = 4): Integer;
begin
  DefRet := x * 10 + y;
end;

procedure TC.Work;
begin
  { multi-element: the surplus arguments are the ones the loop used to append
    as separate slots }
  Write('elided-2  '); Desc('a', 1);
  Write('bracket-2 '); Desc(['a', 1]);

  { single element: arity MATCHES, nothing surplus, and it crashed too }
  Write('elided-1  '); Desc('a');
  Write('bracket-1 '); Desc(['a']);

  { five, mixed tags -- a descriptor that is merely mis-shaped shows here }
  Write('elided-5  '); Desc('s', 1, True, 'c', 2);
  Write('bracket-5 '); Desc(['s', 1, True, 'c', 2]);

  { the bounded loop's controls: ordinary arity, trailing defaults, none }
  Def;
  Def(7);
  Def(7, 8);
  NoArg;
  NoArg();

  { THE EXPRESSION TWIN OF EVERY ROW ABOVE. This is a different parser arm --
    the bare implicit-Self FACTOR -- and it was the same loop with none of the
    doors until both were routed through one routine. `n=` rows must match
    their statement counterparts exactly; if the two halves of this file ever
    disagree, the copy came back. }
  WriteLn('x-elided-2  n=', DescLen('a', 1),          ' tlast=', DescTag('a', 1));
  WriteLn('x-bracket-2 n=', DescLen(['a', 1]),         ' tlast=', DescTag(['a', 1]));
  WriteLn('x-elided-1  n=', DescLen('a'),              ' tlast=', DescTag('a'));
  WriteLn('x-bracket-1 n=', DescLen(['a']),            ' tlast=', DescTag(['a']));
  WriteLn('x-elided-5  n=', DescLen('s', 1, True, 'c', 2),
                            ' tlast=', DescTag('s', 1, True, 'c', 2));
  WriteLn('x-bracket-5 n=', DescLen(['s', 1, True, 'c', 2]),
                            ' tlast=', DescTag(['s', 1, True, 'c', 2]));
  WriteLn('x-def-0     ', DefRet);
  WriteLn('x-def-()    ', DefRet());
  WriteLn('x-def-1     ', DefRet(7));
  WriteLn('x-def-2     ', DefRet(7, 8));
  { inside a `with`, which reaches the same arm and had the same holes }
  with Self do
  begin
    WriteLn('x-with-2    n=', DescLen('a', 1), ' tlast=', DescTag('a', 1));
    WriteLn('x-with-def  ', DefRet(7));
  end;
end;

var c: TC;
begin
  c := TC.Create;
  c.Work;
end.
