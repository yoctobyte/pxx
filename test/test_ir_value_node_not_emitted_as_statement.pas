program test_ir_value_node_not_emitted_as_statement;
{ Guards the statement-vs-value classification that every backend walker asks.

  The walker visits EVERY IR node, value nodes included. Emitting a value node
  at statement level does not merely waste instructions -- the parent that
  consumes it emits it AGAIN, so the whole subtree runs TWICE, side effects and
  all. IR_ATOMIC is the canonical instance: a read-modify-write ran twice and a
  single InterLockedIncrement moved 10 to 12 while answering the post value.
  IR_VIRTUAL_CALL was the same mechanism (57e35555e) and reached the backlog as
  a string allocation count of 7707 against 3799.

  x86-64's walker is an ALLOWLIST and has no statement-level catch-all, so it
  never had this bug. The other five were DENYLISTS -- name the value kinds,
  `else` emit -- which made the DEFAULT for an unnamed kind "emit" on five
  targets and "skip" on x86-64. The five lists then drifted apart and disagreed
  on 8 of the 24 kinds any of them named. IRKindIsStatement in ir.inc is now the
  single source of truth.
  bug-a-the-xtensa-statement-walker-emits-any-unnamed-node-kind-through-a-silent-else

  THIS TEST CANNOT FAIL ON TODAY'S TREE -- that is the point of a guard, and it
  is why the break was verified rather than assumed. DELIBERATE BREAK MEASURED
  2026-09-02: adding IR_ATOMIC to IRKindIsStatement's list (i.e. mis-classifying
  one value kind as a statement, exactly the historical bug) makes this exit 81
  -- n = 12 -- on i386, aarch64 and arm32, and leaves x86-64 at 0 because its
  walker has no catch-all to poison. The assertion is on the COUNT, not on the
  returned value: a doubled rmw still returns a plausible number, so a row that
  only checked `r` would pass while n was wrong. }
{$mode objfpc}
var n, r: Integer;
begin
  n := 10;
  r := InterLockedIncrement(n);
  { correct: exactly one increment. Doubled: n = 12. }
  if n <> 11 then Halt(80 + (n - 11));
  if r <> 11 then Halt(70);
  WriteLn('IRSTMTCLASS OK');
  Halt(0);
end.
