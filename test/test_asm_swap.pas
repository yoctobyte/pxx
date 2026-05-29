program AsmSwap;
{ Statement-level inline asm reading/writing locals by name (FPC swap idiom).
  The clobber list after 'end' is parsed and ignored. }

procedure DoSwap;
var
  n, m: longint;
begin
  n := 42;
  m := -7;
  writeln(n);   { 42 }
  writeln(m);   { -7 }
  asm
    mov eax, n
    xchg eax, m
    mov n, eax
  end ['eax'];
  writeln(n);   { -7 }
  writeln(m);   { 42 }
end;

begin
  DoSwap;
end.
