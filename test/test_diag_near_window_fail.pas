program test_diag_near_window_fail;
{ MUST NOT COMPILE. The point of this file is the DIAGNOSTIC, not the program.

  The `near:` window is described in lexer.inc as "the difference between a
  findable error and an unfindable one", and for the life of the code it printed
  a line's identifiers and silently discarded its syntax -- `x := (1 ;` rendered
  as `near: begin x    >>>  end`, dropping ':=', '(', '1' and ';', which are
  precisely the characters a syntax error is about. Nothing failed, so nothing
  caught it; there was no test anywhere on `near:` CONTENT.

  So this asserts the window's exact text. It is the observable that separates a
  complete fix from a convincing one: nothing here crashes or miscompiles when
  the window degrades, it just quietly says less.
  bug-a-the-token-pool-stores-text-only-for-identifiers-and-strings }
var x: Integer;
begin
  x := (1 ;
end.
