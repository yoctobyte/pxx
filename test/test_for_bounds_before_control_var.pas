program TestForBoundsBeforeControlVar;
{ ISO Pascal, Delphi and FPC all evaluate a `for` loop's INITIAL and FINAL
  expressions BEFORE assigning the control variable. pxx assigned the control
  variable first and lowered the limit after, so a limit that MENTIONS the
  control variable read the value just stored:

    n := 5; for n := 1 to n do        ran 1 iteration, FPC runs 5
    n := 5; for n := 1 to n - 1 do    ran 0,             FPC runs 4
    n := 9; for n := 3 downto n - 8   ran 9,             FPC runs 3

  Silent -- no diagnostic, no crash, just a wrong iteration count. Found only
  because the wrong count happened to index out of bounds and segfault; a
  version that merely looped the wrong number of times would have produced a
  plausible wrong answer and been believed. Nobody writes `for n := 1 to n`
  deliberately, but it arrives from a computed bound reusing a scratch
  variable -- `n := min(i, j); for n := 1 to n do` -- which is ordinary code.

  THREE lowerings implement this one rule, and each is asserted here: the IR
  arm (ir.inc AN_FOR), the stackless-generator state machine (SLLowerFor), and
  the stackful generator. The stackless arm had the identical defect and was
  found only by testing it -- the stackful arm was already correct, so shape
  alone would have pointed at the wrong one.

  Every expectation is FPC 3.2.2's own output for the plain form; the generator
  forms have no FPC oracle (a pxx extension) and are asserted against the plain
  form, which is the same language rule.
  bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned }
uses slgen, coroutine;

var n, c, i, calls: Integer;

function Bump: Integer;
begin
  Inc(calls);
  Bump := 3;
end;

function Start: Integer;
begin
  Write('S');
  Start := 1;
end;

function Lim: Integer;
begin
  Write('L');
  Lim := 3;
end;

function SlUp(n: Integer): Integer; generator; stackless;
begin
  for n := 1 to n do yield n;
end;

function SlDown(n: Integer): Integer; generator; stackless;
begin
  for n := 3 downto n - 8 do yield n;
end;

function CoUp(n: Integer): Integer; generator;
begin
  for n := 1 to n do yield n;
end;

function CoDown(n: Integer): Integer; generator;
begin
  for n := 3 downto n - 8 do yield n;
end;

var x: Integer;
begin
  n := 5; c := 0;
  for n := 1 to n do Inc(c);
  WriteLn('up        ', c);

  n := 5; c := 0;
  for n := 1 to n - 1 do Inc(c);
  WriteLn('up-minus  ', c);

  n := 9; c := 0;
  for n := 3 downto n - 8 do Inc(c);
  WriteLn('down      ', c);

  { the control variable in the INITIAL expression -- always worked }
  n := 5; c := 0;
  for n := n to 7 do Inc(c);
  WriteLn('init-var  ', c);

  { the limit is still evaluated EXACTLY once -- the other end of this window }
  calls := 0; c := 0;
  for i := 1 to Bump do Inc(c);
  WriteLn('once      ', c, ' calls=', calls);

  { SIDE-EFFECT ORDER: initial expression first, then the limit. This is why
    the fix materialises BOTH bounds instead of just swapping two statements. }
  c := 0;
  Write('order     ');
  for i := Start to Lim do Inc(c);
  WriteLn(' ', c);

  { the idiom it actually arrives from }
  i := 7; n := 4;
  if i < n then n := i;
  c := 0;
  for n := 1 to n do Inc(c);
  WriteLn('scratch   ', c);

  { ordinary loops, which must keep working }
  c := 0; for i := 1 to 10 do Inc(c); WriteLn('const     ', c);
  n := 4; c := 0; for i := 1 to n do Inc(c); WriteLn('plainvar  ', c);

  { the same rule through the two generator lowerings }
  c := 0; for x in SlUp(5) do Inc(c);   WriteLn('sl-up     ', c);
  c := 0; for x in SlDown(9) do Inc(c); WriteLn('sl-down   ', c);
  c := 0; for x in CoUp(5) do Inc(c);   WriteLn('co-up     ', c);
  c := 0; for x in CoDown(9) do Inc(c); WriteLn('co-down   ', c);
end.
