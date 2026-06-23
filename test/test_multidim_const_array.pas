program test_multidim_const_array;

{ Multidimensional typed-constant arrays: ND bounds in the const path + a nested
  `((..),(..))` initializer flattened row-major into the 1-D backing store. }

const
  M: array[0..1,0..1] of integer = ((1,2),(3,4));
  T: array[1..2,1..3] of integer = ((10,20,30),(40,50,60));
  C: array[0..1,0..1,0..1] of integer = (((1,2),(3,4)),((5,6),(7,8)));

procedure loc;
const L: array[0..1,0..1] of integer = ((7,8),(9,10));
begin
  writeln(L[0,0],' ',L[0,1],' ',L[1,0],' ',L[1,1]);
end;

begin
  writeln(M[0,0],' ',M[0,1],' ',M[1,0],' ',M[1,1]);   { 1 2 3 4 }
  writeln(T[1,1],' ',T[1,3],' ',T[2,1],' ',T[2,3]);   { 10 30 40 60 }
  writeln(C[0,0,0],' ',C[0,1,1],' ',C[1,0,0],' ',C[1,1,1]); { 1 4 5 8 }
  loc;                                                 { 7 8 9 10 }
  loc;
end.
