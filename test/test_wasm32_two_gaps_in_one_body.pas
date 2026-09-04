{ A BODY WITH TWO DISTINCT wasm32 REFUSALS IN IT, and nothing else.

  This file is not a feature test. It is the SUBJECT of the Makefile row that
  guards the wasm32 coverage report's `and also` listing: the report used to
  keep the FIRST refusal per body and discard the rest, so a body with three
  unrelated gaps reported one, and three tests sat excluded from this target
  under a single wrong cause. The guard needs a body whose report has two
  reasons, and asserts their TEXT rather than a count -- a count row passes on
  a body that refuses the same op twice, which is what the dedup exists to
  prevent. bug-a-the-wasm32-coverage-report-shows-one-refusal-per-body

  WHY THIS CONSTRUCT AND NOT A REAL PROGRAM. The guard's population is the set
  of ops wasm32 does NOT implement, and the whole project is emptying that set,
  so any subject drawn from it goes stale by being FIXED. It has happened
  once already: the row used to name test_static_string_literal, whose two gaps
  were `string operand of type QWord` and `` `=` on strings `` -- both closed
  when the compare-operand classifier learned to read the IR tag in both
  directions, and that file now runs on wasm32 and matches x86-64 row for row.

  So the subject here is deliberately a construct NOBODY WILL IMPLEMENT rather
  than one nobody has got to yet. Comparing an AnsiString against a raw Pointer
  is a programmer error: FPC rejects it outright, pxx accepts it (accepting what
  FPC rejects is not a defect), and there is no meaning to give it -- so wasm32
  refusing it is a permanent, correct answer and not a gap anyone is queuing to
  close. That is the property the guard needs and a real gap cannot have.

  The two reasons come from ONE expression, which is the other requirement: the
  refusal latch short-circuits the statement walk, so a second gap in a LATER
  statement is never reached. `s = Pointer(p)` classifies as a string compare
  from the left operand's tag, then WasmStrParts refuses the right one by name,
  then WasmEmitBinop refuses the operator -- two reasons, one binop, neither
  guarding on the latch.

  IF THIS FILE EVER STOPS PRODUCING TWO REASONS, find a new subject rather than
  weakening the row: compile the corpus for wasm32 and grep the reports for
  `and also`. A body with two gaps is what the row needs; a body with one is
  the defect it exists to catch.

  This program is COMPILED for its report and never run. On x86-64 it compiles
  and produces some answer, which is meaningless by construction. }
program test_wasm32_two_gaps_in_one_body;
var s: AnsiString; p: Pointer; b: Boolean;
begin
  s := 'ab';
  p := nil;
  b := s = Pointer(p);
  WriteLn(b);
end.
