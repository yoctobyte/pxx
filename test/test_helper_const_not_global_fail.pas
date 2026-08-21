program test_helper_const_not_global_fail;
{$mode objfpc}{$h+}
{ A const declared inside a helper is NOT a global. It was one until
  2026-08-21: an untyped helper const was registered as an ordinary global
  symbol, so its bare name resolved anywhere in the program. FPC 3.2.2 refuses
  that — measured on the `type helper for LongWord` spelling FPC accepts:

      hc.pas(14,21) Error: (5000) Identifier not found "BITS"

  ee388cf3a closed the leak while giving typed class/record consts their own
  backing symbol, and test_record_helper_for_string_b331 went red because it
  was asserting the leak (`Writeln('bits: ', BITS)`, commented "global scope").
  That test now reads the const qualified; this one exists so nothing quietly
  re-opens the hole — a passing sibling that reads it QUALIFIED cannot tell the
  difference.

  Both arms on purpose: the untyped form (no symbol, folded as a literal) and
  the typed one (real storage, mangled backing name) reach the const through
  different machinery, so a regression can return on either.
  bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program is the
  sibling story — a commit that exposes a divergence is not the one that
  caused it.

  No clean negative control exists for this one, and saying so is better than
  implying one: `pinned` DOES reject this program, but on the line above
  ("class method not found: WIDTH") — it predates qualified typed-const access
  entirely, so it never reaches the bare read. The test is forward-looking: it
  locks behaviour that is correct today, it is not evidence about yesterday. }
type
  TU32Helper = record helper for Cardinal
    const BITS = 32;             { untyped: a literal, no backing symbol }
    const WIDTH: Integer = 64;   { typed: real storage, mangled backing name }
  end;
begin
  Writeln('qualified untyped: ', TU32Helper.BITS);
  Writeln('qualified typed:   ', TU32Helper.WIDTH);
  Writeln('bare: ', BITS, WIDTH);      { must be REFUSED — neither name is global }
end.
