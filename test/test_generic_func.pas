program TestGenericFunc;

function generic(T) Max(A, B: T): T;
begin
  if A < B then Result := B else Result := A;
end;

function generic(T) Min(A, B: T): T;
begin
  if A > B then Result := B else Result := A;
end;

begin
  writeln(Max<Integer>(3, 7));
  writeln(Max<Integer>(10, 4));
  writeln(Min<Integer>(3, 7));
  writeln(Min<Integer>(10, 4));
end.
