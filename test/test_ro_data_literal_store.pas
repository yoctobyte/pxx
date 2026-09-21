program test_ro_data_literal_store;
{ The read-only data segment IS the instrument: the string-literal pool is
  loaded R-only on x86-64, i386, aarch64 and arm32 executables, so a store to a
  literal faults instead of landing. Two Makefile rows per target: this program
  must DIE of SIGSEGV by default, and must run to the end under --no-ro-data.

  TAKE THE POOL POINTER STRAIGHT FROM THE LITERAL. `p: PChar; p := 'literal'`
  aliases the pool at every -O level -- measured 2026-09-21 over the full
  population this fixture has rows for, x86-64 / i386 / aarch64 / arm32 at
  -O0..-O3, both arms: 16 default builds fault, 16 --no-ro-data builds print
  `after: Xiteral` and exit 0. Stated because the per-backend twins carry their
  own `OptLevel >= 2` gates, so "measured on x86-64" would not have covered the
  three cross targets, and the claim is the fixture's whole premise.
  Do NOT reach it through a string variable
  (`s := 'literal'; p := PChar(s)`), which is what this fixture did until
  2026-09-21 -- that form asks a question whose ANSWER DEPENDS ON -O, because
  EmitStaticLitHandle (compiler/ir_codegen.inc, and its per-backend twins) is
  gated `OptLevel < 2`: a string literal ASSIGNMENT aliases the pool at -O2 and
  above and takes a PXXStrFromLit heap copy below it. Through a string, then,
  the store lands harmlessly in that copy at -O0/-O1 and faults at -O2/-O3, and
  the fixture tests the read-only segment at only half the levels it runs at.
  optdiff.sh reports the rest as `rc 0 vs 139` and is right to.

  WHAT WOULD SPRING THIS. The default arm stops faulting if either the segment
  stops being read-only or the pointer stops pointing into it, and the
  --no-ro-data control separates them: it runs to completion at every level, so
  a default arm that also runs to completion while the control still does means
  the POINTER moved, not the permission. Aliasing itself is not this fixture's
  subject and needs no row here -- test_static_string_literal.pas owns it,
  including a shared block written through and the release path.

  Why a literal needs no copy and no retain is written once, in
  EmitStaticLitHandle; it is not repeated here. }
var p: PChar;
begin
  p := 'literal';
  WriteLn('before: ', p);
  p[0] := 'X';
  WriteLn('after: ', p);
end.
