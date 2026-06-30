{$DECLORDER OFF}
program test_decl_order_lax;
{ {$DECLORDER OFF} (== --lax-decl-order) restores the old lenient behavior: a body
  may read a global declared later in the same scope. Strict (the default) rejects
  this — see test_decl_order_global_error.pas. feature-implicit-identifier-binding-
  strictness-switch. }

procedure Show;
begin
  writeln(G);          { G is declared AFTER this body — allowed only under lax }
end;

var G: Integer;
begin
  G := 42;
  Show;                { 42 }
end.
