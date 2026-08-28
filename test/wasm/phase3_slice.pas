{ SPDX-License-Identifier: MPL-2.0 }
{ Phase 3 slice oracle — control flow. Same two-role shape as phase2_slice.pas:
  built natively it PRINTS, built with -dWASM_NOMAIN its main is empty and the
  harness calls the exported functions and diffs.

  wasm has no jumps. Everything here becomes one `br_table` dispatch loop over
  basic blocks (see the control-flow section of ir_codegen_wasm32.inc), and the
  point of this file is that a dispatch is very easy to get *nearly* right: an
  off-by-one in a block index, a branch depth counted from the wrong nesting,
  or a stale $pc all produce a module that validates perfectly and runs the
  wrong code. The validator has nothing to say about any of them. Only running
  it against the native build does.

  So each function is chosen to fail LOUDLY under a plausible dispatch bug:

    Max3       nested if/else — a wrong block index picks the wrong arm, and
               the three arms return three different values.
    SumTo      a while loop, so the back edge is exercised: a dispatch that
               falls through instead of re-entering the loop returns after one
               iteration, and 55 becomes 1.
    FactW      the same loop carrying Int64s, because the loop counter and the
               accumulator are different widths.
    ForSum     `for ... to`, ForDown `for ... downto` — the two directions have
               different bound comparisons (tkLe vs tkGe) and different
               signedness handling.
    RepUntil   repeat/until: the test is at the BOTTOM, so a body that runs
               zero times instead of once is the classic off-by-one and the
               answer differs.
    CaseOf     a case with a single value, a value list and a range, plus an
               else — several arms sharing one dispatch.
    BreakCont  break and continue inside a for loop, which branch out of and
               back into a loop that is not the innermost block.
    ShortC     short-circuit and/or, which the frontend lowers to control flow
               rather than to an operator.
    EarlyExit  `Exit` — a branch clean out of the dispatch to the epilogue.
    NestLoop   a loop inside a loop, where an outer-loop branch has to count
               past the inner loop's blocks to find its target.
    GotoSum    an explicit `goto`, which is the only construct here that can
               produce a CFG the structured forms cannot — every other function
               has a reducible shape the frontend built, this one has whatever
               the programmer wrote. It is in the phase's milestone and would
               otherwise be the one form claimed without evidence. }
program Phase3Slice;

function Max3(a, b, c: Integer): Integer;
begin
  if a >= b then
  begin
    if a >= c then Max3 := a else Max3 := c;
  end
  else if b >= c then Max3 := b
  else Max3 := c;
end;

function SumTo(n: Integer): Integer;
var i, s: Integer;
begin
  s := 0; i := 1;
  while i <= n do begin s := s + i; i := i + 1; end;
  SumTo := s;
end;

function FactW(n: Int64): Int64;
var r, i: Int64;
begin
  r := 1; i := 2;
  while i <= n do begin r := r * i; i := i + 1; end;
  FactW := r;
end;

function ForSum(n: Integer): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to n do s := s + i * i;
  ForSum := s;
end;

function ForDown(n: Integer): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := n downto 1 do s := s * 2 + i;
  ForDown := s;
end;

function RepUntil(n: Integer): Integer;
var s: Integer;
begin
  s := 0;
  repeat s := s + n; n := n - 1; until n <= 0;
  RepUntil := s;
end;

function CaseOf(n: Integer): Integer;
begin
  case n of
    0: CaseOf := 100;
    1, 2: CaseOf := 200;
    3..5: CaseOf := 300;
  else CaseOf := 900;
  end;
end;

function BreakCont(n: Integer): Integer;
var i, s: Integer;
begin
  s := 0;
  for i := 1 to n do
  begin
    if i = 3 then continue;
    if i = 7 then break;
    s := s + i;
  end;
  BreakCont := s;
end;

function ShortC(a, b: Integer): Integer;
begin
  if (a > 0) and (b > 0) then ShortC := 1
  else if (a > 0) or (b > 0) then ShortC := 2
  else ShortC := 3;
end;

function EarlyExit(n: Integer): Integer;
begin
  EarlyExit := -1;
  if n < 0 then Exit;
  EarlyExit := n * 2;
end;

function NestLoop(n: Integer): Integer;
var i, j, s: Integer;
begin
  s := 0;
  for i := 1 to n do
  begin
    j := 0;
    while j < i do
    begin
      s := s + 1;
      j := j + 1;
    end;
    if s > 20 then break;
  end;
  NestLoop := s;
end;

function GotoSum(n: Integer): Integer;
label top, done;
var i, s: Integer;
begin
  s := 0; i := 1;
top:
  if i > n then goto done;
  s := s + i;
  i := i + 1;
  goto top;
done:
  GotoSum := s;
end;

{$ifndef WASM_NOMAIN}
begin
  writeln(Max3(3, 1, 2));
  writeln(Max3(1, 3, 2));
  writeln(Max3(1, 2, 3));
  writeln(SumTo(10));
  writeln(SumTo(0));
  writeln(FactW(20));
  writeln(FactW(1));
  writeln(ForSum(5));
  writeln(ForSum(0));
  writeln(ForDown(5));
  writeln(RepUntil(4));
  writeln(RepUntil(0));
  writeln(CaseOf(0));
  writeln(CaseOf(2));
  writeln(CaseOf(4));
  writeln(CaseOf(9));
  writeln(BreakCont(10));
  writeln(ShortC(1, 1));
  writeln(ShortC(1, -1));
  writeln(ShortC(-1, -1));
  writeln(EarlyExit(-5));
  writeln(EarlyExit(21));
  writeln(NestLoop(3));
  writeln(NestLoop(100));
  writeln(GotoSum(10));
  writeln(GotoSum(0));
end.
{$else}
begin
end.
{$endif}
