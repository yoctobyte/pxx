{ Constant SET EXPRESSIONS: one set constant defined from another, with the set operators.

      ValueJSONTypes       = [jtNumber, jtString, jtBoolean, jtNull];
      ActualValueJSONTypes = ValueJSONTypes - [jtNull];      { fpjson }

  Only a bare `[...]` literal used to parse; a named set on the right-hand side fell into
  the integer ConstEval and died there ("ConstEval error"). Terms are now a literal OR the
  name of an earlier set constant, combined left-associatively with + (union), - (difference)
  and * (intersection). }
program test_set_const_expr_b281;
type TE = (a, b, c, d);
const
  S1 = [a, b, c];
  SA = S1 - [a];         { expect b,c }
  SB = S1 - [b];         { expect a,c }
  SC = [a, b, c] - [b];  { literal - literal: expect a,c }
  SD = S1;               { named alone: expect a,b,c }
  SE = [a] + [c, d];     { union: expect a,c,d }
  SF = S1 * [b, c, d];   { intersection: expect b,c }
  SG = S1 + [d] - [a];   { left-assoc chain: expect b,c,d }
var x: set of TE;
procedure Show(const nm: string; s: set of TE);
begin
  write(nm, ': ');
  if a in s then write('a');
  if b in s then write('b');
  if c in s then write('c');
  if d in s then write('d');
  writeln;
end;
begin
  x := S1; Show('S1', x);
  x := SA; Show('SA', x);
  x := SB; Show('SB', x);
  x := SC; Show('SC', x);
  x := SD; Show('SD', x);
  x := SE; Show('SE', x);
  x := SF; Show('SF', x);
  x := SG; Show('SG', x);
end.
