{ A template's method bodies must materialise where the SPECIALIZATION is
  visible, not where the template happens to be parsed.

  Under a circular implementation-`uses` the specializing unit runs NESTED
  INSIDE the template unit's own implementation, so the template's bodies have
  not been walked yet: nothing was buffered, nothing was pended, and the body
  was instead streamed much later into the TEMPLATE's unit, where the
  specialization's name does not exist. `expected 'begin' before '.'`, reported
  against a file whose text is fine, because spliced tokens carry the template's
  source offsets.

  The numbers are the point, not the exit code: each template's Bump adds a
  DIFFERENT constant, so a body materialised against the wrong template prints a
  wrong number rather than passing. 20 is the input to all three, and 21/22/23
  separate the three templates -- a probe whose right answer cannot collide with
  another arm's.

  fpc 3.2.2 runs all three arms and agrees. tgeneric91.pp is the mutual arm.
  bug-p-a-specialized-method-body-splices-into-an-illegal-place-under-circular-uses }
program test_a_specialized_body_materialises_under_circular_uses;
uses ucircgena, ucircgenb, ucircgenc;
begin
  TDrvA.Run;
  TDrvB.Run;
  TDrvC.Run;
end.
