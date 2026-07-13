{ Bare, PARENLESS call of a proc-var / method-pointer as a STATEMENT: `AMethod;`
  (fpcunit's AssertException invokes the TRunMethod it was handed exactly so).

  POSITION is the only thing that disambiguates this. A bare proc-var name is a
  VALUE nearly everywhere -- `q := p`, `Foo(cb)`, `Assigned(p)` -- and is a CALL only
  when the whole statement is the name. This test pins BOTH halves: the call forms
  must call, and every value position must still yield the pointer, not invoke it.

  (The first attempt put the rule in ParseLValueAST, which also parses expression
  atoms -- where the next token is just as often a ';'. That turned `q := p;` into a
  call of p. Hence the value half below.) }
program test_bare_procvar_call_b273;

type
  TProc = procedure;
  TFunc = function: Integer;
  TMeth = procedure of object;
  TC = class
    n: Integer;
    procedure M;
  end;

var calls: Integer;

procedure TC.M;
begin
  Inc(calls);
  writeln('meth n=', n);
end;

procedure P;
begin
  Inc(calls);
  writeln('plain');
end;

function F: Integer;
begin
  Inc(calls);
  Result := 7;
end;

{ a proc-var PARAM, called bare inside the callee }
procedure Takes(cb: TProc);
begin
  writeln('param assigned: ', Assigned(cb));   { VALUE }
  cb;                                          { CALL }
end;

var
  pp, qq: TProc;
  ff: TFunc;
  mm: TMeth;
  c: TC;
begin
  calls := 0;
  pp := @P;

  { ---- VALUE positions: none of these may call ---- }
  qq := pp;                                { plain assignment }
  writeln('assigned: ', Assigned(pp));
  writeln('same: ', pp = qq);
  writeln('calls so far: ', calls);        { must still be 0 }

  { ---- CALL positions ---- }
  pp;                                      { bare statement }
  pp();                                    { explicit empty parens }
  qq;                                      { through the copy }
  Takes(pp);                               { value in, call inside }

  ff := @F;
  ff;                                      { a FUNCTION proc-var as a statement:
                                             the result is discarded }
  writeln('func via parens: ', ff());

  c := TC.Create;
  c.n := 5;
  mm := @c.M;
  writeln('meth assigned: ', Assigned(mm));  { VALUE }
  mm();                                      { CALL, parens }
  mm;                                        { CALL, bare -- the fpcunit shape }

  writeln('total calls: ', calls);
end.
