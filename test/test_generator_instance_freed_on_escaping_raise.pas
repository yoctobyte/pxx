program TestGeneratorInstanceFreedOnEscapingRaise;
{ bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in

  The for-in generator desugar ran its teardown -- SlFree (stackless) or CoFree
  (stackful) -- as a TRAILING STATEMENT after the loop. An exception raised in
  the generator body or in the loop body propagates to an enclosing handler and
  walks straight past it, so the instance was never freed; `exit` out of the
  loop skipped it the same way. It is now a FINALIZER (AN_TRY_FINALLY), which is
  the shape the class-enumerator for-in in the same file had all along.

  MEASURED at N=2000 / N=8000, slope (the census prints at geometric
  thresholds, so a raw live count divided by N is wrong):

    row                                    before            after
    stackless raise escapes the for-in     0.936 blocks/raise  FLAT (live 2)
    stackful  raise escapes the for-in     4.40 kB RSS/raise   FLAT (392 kB)

  The stackful slope is TOUCHED PAGES; the address space lost was the whole
  CO_STACK, 64 KB per escaping raise. Its `before` could only be measured after
  bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler,
  because until then the raise killed the process instead of leaking.

  `exitsum` and `breaksum` cover the other two skip paths: leaving the loop
  early by `exit` and by `break`. Those needed a second fix -- the finally body
  reached by IRLowerCleanupToDepth was not marked as a statement, so a finalizer
  that is a BARE CALL node was not emitted at all on the exit/break/continue
  paths. A source-level `try ... finally F; end` never showed it (the parser
  always hands over an AN_SEQ, and sequence lowering marks its own statements),
  so exit/break/continue past a value-returning finalizer all measured GREEN
  while this leaked one instance per early exit.

  ROW `nest` IS THE ONE THAT MUST NOT MOVE, and it is not decoration. Wrapping
  the loop unconditionally turned this working program into a COMPILE ERROR:
  inside a stackless generator the `yield` would then sit in a try/finally, and
  SLCheckEligible rejects that ("yield only allowed at top level or inside
  for/while/if/case") because the flattener cannot split a state machine across
  a finally frame. So a stackless consumer that suspends inside the loop keeps
  the trailing free, and keeps the leak on its own unwind path -- measured at
  0.999 instances per escaping raise for `for v in Inner(n) do yield v * 10`,
  where the OUTER instance is now freed and the INNER one is not. That residual
  is deliberately NOT in this program: it would have to relax the bound below
  from 50 to thousands, and a guard that tolerates the leak next door cannot
  see this one come back. It is recorded in the ticket instead. }
uses coroutine, slgen, sysutils;

const N = 2000;

var caught: Integer;

function GenSL(n: Integer): Integer; generator; stackless;
begin
  yield n;
  raise Exception.Create('sl');
end;

function GenSF(n: Integer): Integer; generator;
begin
  yield n;
  raise Exception.Create('sf');
end;

function Count(n: Integer): Integer; generator; stackless;
var i: Integer;
begin
  for i := 1 to n do yield i;
end;

{ The shape the eligibility guard protects: a stackless generator whose loop
  body yields. It consumes another generator, so it is the desugar under test. }
function Times10(n: Integer): Integer; generator; stackless;
var v: Integer;
begin
  for v in Count(n) do
    yield v * 10;
end;

procedure OnceSL;
var x: Integer;
begin
  try
    for x in GenSL(1) do
      if x = 0 then writeln('never');
  except
    on E: Exception do Inc(caught);
  end;
end;

procedure OnceSF;
var x: Integer;
begin
  try
    for x in GenSF(1) do
      if x = 0 then writeln('never');
  except
    on E: Exception do Inc(caught);
  end;
end;

{ Leaves the loop with the generator still un-exhausted -- `exit` unwinds the
  whole frame, `break` only the loop, and they reach the teardown by different
  call sites in IRLowerCleanupToDepth. }
function OnceExit: Integer;
var x, acc: Integer;
begin
  acc := 0;
  for x in Count(5) do
  begin
    acc := acc + x;
    OnceExit := acc;
    if x = 2 then Exit;
  end;
  OnceExit := acc;
end;

function OnceBreak: Integer;
var x, acc: Integer;
begin
  acc := 0;
  for x in Count(5) do
  begin
    acc := acc + x;
    if x = 2 then Break;
  end;
  OnceBreak := acc;
end;

var i, exitsum, breaksum, nest, y: Integer;
begin
  caught := 0;
  for i := 1 to N do OnceSL;
  writeln('caught_sl=', caught);

  caught := 0;
  for i := 1 to N do OnceSF;
  writeln('caught_sf=', caught);

  exitsum := 0;
  for i := 1 to N do exitsum := exitsum + OnceExit;
  writeln('exitsum=', exitsum);

  breaksum := 0;
  for i := 1 to N do breaksum := breaksum + OnceBreak;
  writeln('breaksum=', breaksum);

  nest := 0;
  for y in Times10(4) do nest := nest + y;
  writeln('nest=', nest);
end.
