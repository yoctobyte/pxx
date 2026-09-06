{ Pascal's relational level is ONE precedence level and it is LEFT-ASSOCIATIVE:
  `=`, `<>`, `<`, `<=`, `>`, `>=`, `in`, `is` and `as` all sit on it, so
  `MS in Switches = Enable` means `(MS in Switches) = Enable`. pxx gave each of
  `in`, `is` and `as` a level of its own that nothing could follow, and never
  chained two comparisons at all -- every row below except the parenthesised
  controls answered `expected 'then' before '='`.

  fcl-passrc pscanner.pp:3806 is `if MS in CurrentModeSwitches=Enable then`,
  which is why this was a wall and not a curiosity.

  r4 is the row that pins the ASSOCIATIVITY rather than the parse, and it took
  three attempts to find one that could. Booleans cannot do it -- `=` and `<>`
  over Booleans are XNOR and XOR, both associative, so every all-Boolean chain
  prints the same value under either grouping. Mixing an Integer in is what
  separates them: `i < 2 = b` is `(1 < 2) = True` = TRUE left-associatively,
  and `1 < (2 = True)` = `1 < FALSE` = FALSE the other way. fpc REFUSES the
  right-hand grouping outright (Integer against Boolean) while pxx accepts it,
  so under pxx the wrong reading is a wrong VALUE and not a refusal -- which is
  exactly the row a compile-only test would miss.
  bug-p-a-relational-operator-cannot-follow-in-is-or-another-comparison }
{$mode objfpc}
program test_a_relational_operator_can_follow_in_is_and_a_comparison;
type
  TS = set of 0..7;
  TA = class end;
  TB = class(TA) end;
var
  s: TS;
  b, c: Boolean;
  i: Integer;
  o: TA;
begin
  s := [1, 3]; b := True; c := False; i := 1; o := TB.Create;
  WriteLn('r1 ', (1 in s) = b);      { control: the parenthesised spelling }
  WriteLn('r2 ', 1 in s = b);
  WriteLn('r3 ', i = 1 = b);         { parses at all; does not pin grouping }
  WriteLn('r4 ', i < 2 = b);         { THE associativity row -- see the header }
  WriteLn('r5 ', (o is TB) = b);     { control }
  WriteLn('r6 ', o is TB = b);
  WriteLn('r7 ', 1 in s <> c);
  WriteLn('r8 ', 2 in s = c);
  WriteLn('r9 ', i > 0 = (1 in s));
end.
