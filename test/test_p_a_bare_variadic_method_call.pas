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

  EVERY CALL BELOW IS A BARE STATEMENT, because that is the loop this file
  guards. The same call written inside an EXPRESSION goes through a different
  arm (pasparser_expr.inc's bare implicit-Self factor), and an earlier version
  of this header claimed that arm "already had the tail". IT DOES NOT -- it is
  the same hand-rolled loop with NONE of the doors, measured 2026-09-09:
  `Desc('a', 1)` in expression position segfaults exactly as the statement
  spelling did, and `Desc(['a', 1])` there answers `n=0` because the bracket is
  still read as a set. That is filed as its own ticket rather than asserted
  here, and this note stays because a claim about a sibling path is the kind a
  reader inherits without re-measuring.
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
end;

var c: TC;
begin
  c := TC.Create;
  c.Work;
end.
