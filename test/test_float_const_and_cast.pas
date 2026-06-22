program test_float_const_and_cast;

{ bug-untyped-float-const: (1) untyped real consts `const X = 1.5;` incl. negative
  and exponent; (2) negative value in a typed float const; (3) value typecast to a
  float type `Single(expr)`/`Double(expr)` as an expression. All FPC-faithful. }

const
  EPS  = 0.001;
  PI   = 3.14159;
  NEG  = -2.5;
  TINY = 1e-3;
  TYPED_NEG: Double = -7.25;
  N    = 42;              { integer untyped const still works }

var d: Double; s: Single; i: Integer;
begin
  WriteLn(EPS:0:4);            { 0.0010 }
  WriteLn(PI:0:5);             { 3.14159 }
  WriteLn(NEG:0:2);            { -2.50 }
  WriteLn(TINY:0:4);          { 0.0010 }
  WriteLn(TYPED_NEG:0:2);     { -7.25 }
  WriteLn(N);                 { 42 }
  WriteLn((PI * 2.0):0:5);    { 6.28318 }

  d := Single(2.5);  WriteLn(d:0:2);     { 2.50  — narrow double->single }
  s := Single(3.0);  WriteLn(s:0:2);     { 3.00 }
  i := 7;
  d := Double(i);    WriteLn(d:0:2);     { 7.00  — int->double }
  d := Single(2.0) + 1.0;  WriteLn(d:0:4);   { 3.0000 — cast in arithmetic }
end.
