program p11;
function S(a, b, c, d, e, f, g, h, i, j, k: Integer): Integer;
begin S := a + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8 + i*9 + j*10 + k*11; end;
function Q(a: Int64; b: Integer; c: Int64; d, e, f, g, h, i, j: Integer): Int64;
begin Q := a + Int64(b) + c + Int64(d+e+f+g+h+i+j); end;
begin
  writeln('S=', S(1,2,3,4,5,6,7,8,9,10,11));
  writeln('Q=', Q(1000000000, 2, 3000000000, 4,5,6,7,8,9,10));
end.
