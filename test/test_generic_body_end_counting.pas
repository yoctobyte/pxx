{ A generic routine's body extent is found by counting `end`s, and the counter
  in pasparser_generic.inc knew only `begin` and `case`. `try` and `asm` also
  close with an `end`, so each drove the count to zero one `end` EARLY: the
  buffered body stopped short and the routine's own closing `end` was left in
  the token stream, where the unit loop's silent tkEnd arm ate it. The unit then
  terminated in the wrong place and the diagnostic surfaced as `unexpected token
  in a unit implementation section` AT THE FILE'S LAST LINE -- for a defect
  anywhere above it. This was the rtl-generics rung-6b wall.

  THREE THINGS THIS TEST IS SHAPED BY, all learned by being wrong first:

  1. THE SUBJECT MUST BE A UNIT. The first draft declared everything in this
     program and the PRE-FIX compiler printed the right answer. Running the test
     against the pinned binary and REQUIRING it to fail is the only reason that
     was caught instead of committed green.

  2. IT ASSERTS VALUES. The failure mode is a body silently truncated, and a
     short body can still parse.

  3. EACH ARM WAS ISOLATED. A first pass put `asm` and a local `record` type in
     one unit, saw it fail, and credited both. Only `asm` is a regression arm;
     `record` passes pre-fix. The unit says which is which and why.

  The generic-FUNCTION copy of the same counter (pasparser_generic.inc:3370) is
  NOT exercised here, and no shape reaches it: pxx rejects a `generic function`
  in a unit interface and in a unit implementation alike, which are the only
  places the miscount could bite, and at program level the pre-fix binary is
  already correct. That gap is bug-p-a-generic-function-cannot-be-declared-in-
  a-unit. The counter there was corrected to match anyway and is unverified BY
  CONSTRUCTION; this paragraph is the record of it.

  Oracle: FPC 3.2.2 prints `9 9 5 9 100` for the arms it will compile -- it
  refuses the `asm` arm ("Assembler blocks not allowed inside generics") and
  raises an internal error on the local-record arm inside a unit, so the run
  that produced those five values used the program form of the same code.
  bug-p-a-generic-method-body-with-try-loses-its-closing-end }
program test_generic_body_end_counting;
uses ugbodyend;

var
  b: specialize TBox<Integer>;
begin
  b := specialize TBox<Integer>.Create;
  writeln(b.TryFinally, ' ', b.TryExcept, ' ', b.WithAsm, ' ', b.LocalRecord,
          ' ', b.CaseStillWorks(1), ' ', b.Tail);
end.
