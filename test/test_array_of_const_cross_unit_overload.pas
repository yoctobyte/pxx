program test_array_of_const_cross_unit_overload;
{ Whether a `[...]` argument is a TVarRec vector or a SET literal has to be
  decided BEFORE overload resolution — the parser cannot parse it otherwise —
  and that question used to be asked of whichever candidate the name resolved
  to FIRST. So the answer depended on uses-clause ORDER: with the
  array-of-const unit listed LAST, `g('%s', ['a'])` failed with

      argument types: (ShortString, set)
      candidates:
        g(Variant, AnsiString)
        g(AnsiString, record)

  Both candidates present, so the cross-unit merge was never the problem — the
  literal had already been parsed as a set and could no longer match anything.
  The failure read as though the CALL were wrong.

  The order below is the one that failed. FPC 3.2.2 accepts the same program.
  bug-a-array-of-const-literal-does-not-match-in-a-cross-unit-overload-set }
uses aoc_ovl_unit_var, aoc_ovl_unit_fmt;
var d: TDays;
begin
  { the regression: array-of-const overload lives in the unit named LAST }
  g('one', ['a']);
  g('two', ['a', 1]);
  g('none', []);
  { ...and its sibling still resolves }
  g(1, 'x');

  { A SET parameter at the same slot VETOES the reinterpretation: `[...]` may
    genuinely be a set there, and guessing the other way would break a working
    call to buy the one above. Only the unambiguous form is asserted here — a
    BRACKET LITERAL where one overload takes a set and another takes
    `array of const` at the same slot is order-dependent in FPC 3.2.2 too, and
    the two implementations disagree on one of the two orders, so pinning it
    would cement an accident. Measured, and escalated as
    decide-set-vs-array-of-const-at-the-same-overload-slot. }
  d := [dTue];
  k(d);
end.
