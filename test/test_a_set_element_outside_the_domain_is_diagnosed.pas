program test_a_set_element_outside_the_domain_is_diagnosed;
{$mode objfpc}{$H+}
{ A set element that is a CONSTANT outside 0..255 is now reported.

  `x in [...]` has two lowerings and they had two different domains, chosen
  silently by whether any element is spelled as a variable. All-constant
  elements become a COMPARE CHAIN, which has the left operand's full Int64
  domain; one variable element switches the whole literal to a 256-bit MASK,
  which is a real Pascal set. So `q in [300]` answered TRUE and `q in [r]` with
  r = 300 answered FALSE -- the same operator on the same values, and nothing
  said so.

  THE VALUES ARE NOT WHAT CHANGED, AND THIS IS NOT AN fpc ORACLE FILE. fpc 3.2.2
  answers FALSE to row A and warns; we answer TRUE and warn. Both are correct
  about their own lowering, and CLAUDE.md is explicit that matching the value a
  compiler produces AFTER it has diagnosed the input is not a goal -- 300 is not
  a set element, the source is already wrong, and the compare chain answers what
  the programmer wrote. What was a defect was that nobody said anything. So this
  file asserts the DIAGNOSTIC, and the Makefile recipe greps for it; the values
  below are pxx's own and are recorded so a future change to them is visible.

  ROW E IS THE POSITIVE CONTROL AND IT IS THE ROW THAT MATTERS MOST. An ordinary
  in-domain char literal must NOT warn. A check that fires on every set literal
  would pass every other row in this file, and would put a false warning into
  the compiler's own build output -- the one stream everybody reads for a single
  token and therefore does not read at all.

  bug-p-the-two-arms-of-in-disagree-about-their-own-domain-silently }

var
  q, r: Int64;
  c: Char;

begin
  q := 300; r := 300;
  WriteLn('A: ', q in [300]);          { constant arm, out of domain  -> warns }
  WriteLn('B: ', q in [r]);            { runtime arm, nothing constant -> silent }

  q := 9; r := 9;
  WriteLn('C: ', q in [4294967297, r]); { runtime arm, CONSTANT element out of domain -> warns }

  q := 7;
  WriteLn('D: ', q in [7]);            { in domain, silent }

  c := 'k';
  WriteLn('E: ', c in ['a'..'z']);     { in domain, silent -- the positive control }

  q := 250;
  WriteLn('F: ', q in [200..300]);     { a RANGE whose high end is out of domain -> warns }
end.
