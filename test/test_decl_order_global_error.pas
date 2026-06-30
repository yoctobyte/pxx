{ A routine must not see a program GLOBAL declared textually after it
  (declare-before-use, FPC-parity). `gLate` is declared below P, so P's
  reference to it must NOT silently bind the later global — the compiler errors.
  Guards the decl-order gating (a stray name binding a distant global was a real
  bug: a `for` loop counter accidentally bound a program-global scratch var). }
program test_decl_order_global_error;
procedure P;
begin
  gLate := 5;        { gLate is declared AFTER this procedure -> must error }
end;
var gLate: Integer;
begin
  P;
end.
