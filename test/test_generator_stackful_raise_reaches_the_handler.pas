program TestGeneratorStackfulRaiseReachesTheHandler;
{ bug-a-an-exception-raised-in-a-stackful-generator-body-does-not-reach-the-for-in-handler

  A raise inside a STACKFUL (`generator;`, coroutine) body used to die with
  `Unhandled exception` even though the driving `for..in` sat inside a
  try/except that caught the same raise from a plain procedure and from a
  `generator; stackless;` body. CoAlloc seeds the coroutine context's saved
  exc_top with 0 -- "fresh chain on this stack" -- and CoSwitch restores it on
  the way in, so the raise walked an EMPTY chain.

  The generator body prologue now links the chain to its resumer's, which is
  what a `call` would have given it. The consumer's chain head needs no new
  intrinsic: it is [[self + CO_OFF_CALLERCTX]], because CoNext passes
  pfrom = &callerctx and CoSwitch pushes exc_top last before storing rsp.

  THE THREE-WAY CONTROL is rows 1-3: the try is the same try and the raise is
  the same raise, and only the form of the raiser changes. Rows 1 and 2 were
  green before the fix and are the controls that say the harness works; row 3
  is the guard. Rows 4 and 5 are the ones that say the fix did not swing too
  far -- a generator must still catch its OWN raise (4) and must still let one
  past its own non-matching handler (5).

  `yield` inside try/except/finally is rejected by the compiler ("v1"), so a
  generator's handler frame can never be live across a suspension -- which is
  why there is no row for "the consumer raises while the generator is suspended
  inside its own try". That case cannot be written.

  NOT GUARDED HERE, and it is measured, not assumed: an exception escaping the
  loop skips the teardown that calls CoFree, so each escaping raise leaks the
  coroutine's 64 KB stack (RSS slope 4.59 KB/raise -- the touched pages, not the
  reservation) plus the instance. That is
  bug-a-a-generator-instance-is-not-freed-when-an-exception-escapes-the-for-in,
  which is why N here is 5 and not 2000. }
uses coroutine, slgen, sysutils;

var gmsg: AnsiString;
    plainC, slC, sfC, innerC, outerC, vals: Integer;

procedure PlainRaiser;
begin
  raise Exception.Create(gmsg + '1');
end;

function GenSL(n: Integer): Integer; generator; stackless;
begin
  yield n;
  raise Exception.Create(gmsg + '2');
end;

function GenSF(n: Integer): Integer; generator;
begin
  yield n;
  raise Exception.Create(gmsg + '3');
end;

{ catches its OWN raise and keeps yielding }
function GenOwn(n: Integer): Integer; generator;
begin
  yield 1;
  try
    raise Exception.Create(gmsg + '4');
  except
    on E: Exception do Inc(innerC);
  end;
  yield 2;
end;

{ a handler that does not fire, then a raise that must reach the consumer }
function GenPast(n: Integer): Integer; generator;
begin
  yield 1;
  try
    if n = 999 then raise Exception.Create(gmsg + 'never');
  except
    on E: Exception do Inc(innerC);
  end;
  raise Exception.Create(gmsg + '5');
end;

var i, x: Integer;
begin
  gmsg := 'boom';
  plainC := 0; slC := 0; sfC := 0; innerC := 0; outerC := 0;

  for i := 1 to 5 do
    try PlainRaiser; except on E: Exception do Inc(plainC); end;
  writeln('plain=', plainC);

  for i := 1 to 5 do
    try
      for x in GenSL(1) do if x = 0 then writeln('never');
    except on E: Exception do Inc(slC); end;
  writeln('stackless=', slC);

  for i := 1 to 5 do
    try
      for x in GenSF(1) do if x = 0 then writeln('never');
    except on E: Exception do Inc(sfC); end;
  writeln('stackful=', sfC);

  vals := 0; innerC := 0;
  for x in GenOwn(1) do Inc(vals);
  writeln('own vals=', vals, ' inner=', innerC);

  vals := 0; innerC := 0; outerC := 0;
  try
    for x in GenPast(1) do Inc(vals);
  except on E: Exception do Inc(outerC); end;
  writeln('past vals=', vals, ' inner=', innerC, ' outer=', outerC);
end.
