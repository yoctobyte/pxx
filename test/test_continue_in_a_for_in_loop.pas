{ `Continue` inside a `for-in` loop HUNG — an infinite loop, in every container
  kind. The desugar built `while cond do begin x := C[i]; BODY; i := i + 1 end`,
  and AN_WHILE's continue target is the CONDITION TEST, so a Continue jumped
  over the increment and re-ran the same element forever. `Break` was fine, and
  so were plain `for` and `while`, whose increments the IR places at the
  continue label itself.

  Fixed by advancing at the TOP: `i := lo - 1; while i < hi do begin
  i := i + 1; x := C[i]; BODY end`. bug-a-continue-in-a-for-in-loop-never-advances }
program test_continue_in_a_for_in_loop;

type
  TC = (rd, gn, bl);
  TCSet = set of TC;

var
  dy: array of Integer;
  a: array[0..4] of Integer;
  lo: array[5..8] of Integer;      { a non-zero low bound — the index shift }
  s: AnsiString;
  cset: TCSet;
  i, n: Integer;
  c: Char;
  e: TC;
  seen: Integer;
begin
  { dynamic array }
  SetLength(dy, 5);
  for i := 0 to 4 do dy[i] := i;
  for n in dy do
  begin
    if Odd(n) then Continue;
    Write(n);
  end;
  WriteLn(' dyn');

  { fixed array }
  for i := 0 to 4 do a[i] := i;
  for n in a do
  begin
    if Odd(n) then Continue;
    Write(n);
  end;
  WriteLn(' fixed');

  { a static array whose index range does NOT start at zero }
  for i := 5 to 8 do lo[i] := i * 2;
  for n in lo do
  begin
    if n = 12 then Continue;
    Write(n, ' ');
  end;
  WriteLn('static');

  { string }
  s := 'abcde';
  for c in s do
  begin
    if c = 'b' then Continue;
    Write(c);
  end;
  WriteLn(' str');

  { enum type }
  for e in TC do
  begin
    if e = gn then Continue;
    Write(Ord(e));
  end;
  WriteLn(' enum');

  { a SET — a third desugar, with the same shape and the same bug. Both the
    set-variable form and the bare set-constructor form. }
  cset := [rd, gn, bl];
  for e in cset do
  begin
    if e = gn then Continue;
    Write(Ord(e));
  end;
  WriteLn(' set');

  for n in [1, 2, 3] do
  begin
    if n = 2 then Continue;
    Write(n);
  end;
  WriteLn(' sctor');

  { Break still works, and still leaves the rest unvisited }
  for n in dy do
  begin
    if n = 3 then Break;
    Write(n);
  end;
  WriteLn(' break');

  { Continue on EVERY iteration must still terminate — the shape that spins
    forever if the advance is reachable only by falling off the body's end }
  seen := 0;
  for n in dy do
  begin
    Inc(seen);
    Continue;
  end;
  WriteLn('all ', seen);

  { the edges: the rewritten bounds must not gain or lose an iteration }
  SetLength(dy, 0);
  seen := 0;
  for n in dy do Inc(seen);
  WriteLn('empty ', seen);

  SetLength(dy, 1);
  dy[0] := 9;
  seen := 0;
  for n in dy do Inc(seen);
  WriteLn('one ', seen, ' ', dy[0]);

  s := '';
  seen := 0;
  for c in s do Inc(seen);
  WriteLn('estr ', seen);
end.
