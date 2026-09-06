{ A `const` section must END at an identifier-spelled SECTION keyword, not
  consume it as the next constant's NAME.

  The terminator list is hand-maintained and had drifted from the type
  section's, which its own comment claimed to mirror: `threadvar`,
  `resourcestring` and `label` are plain identifiers in this dialect, so a
  const block followed by any of them ate the keyword and died on the `=` that
  never came --

      const nFoo = 1030;
      resourcestring SErr = '...';   ->  expected '=' before 'SErr'

  Found by attempting rung 7 of the Pascal corpus ladder (fcl-passrc); this is
  the first wall in FPC's own pscanner.pp, at :74.

  THE LOOP STOPS, IT DOES NOT JUDGE. Whether a section is LEGAL in a given
  position stays the enclosing dispatcher's question, and rows E/F are the
  control for that: fpc 3.2.2 refuses `resourcestring` inside a routine's
  declaration part and so must pxx, which it still does because breaking the
  loop hands the word to a dispatcher that does not accept it. Without those
  rows this file passes just as well if the loop were made to stop at every
  identifier, which would accept anything.

  `threadvar` is deliberately NOT asserted here: it is unsupported at any
  scope (feature-p-threadvar-is-not-supported-at-any-scope) and refuses
  identically with or without a preceding const, so this fix is not what gates
  it. Add a row when that lands.

  .expected is fpc 3.2.2's own output, byte for byte.
  feature-pascal-corpus-expansion }
program test_a_const_section_ends_at_a_section_keyword;

const
  nFoo = 1030;
resourcestring
  SErrA = 'alpha';
  SErrB = 'beta';

procedure WithLabel;
const
  cInner = 7;
label
  L1;
begin
  goto L1;
  WriteLn('D unreachable');
L1:
  WriteLn('D ', cInner);
end;

begin
  WriteLn('A ', nFoo);
  WriteLn('B ', SErrA);
  WriteLn('C ', SErrB);
  WithLabel;
  WriteLn('OK');
end.
