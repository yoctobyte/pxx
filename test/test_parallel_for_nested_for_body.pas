{ A `for` loop INSIDE a `parallel for` body.

  The control variable of a loop is written by the loop, so N workers sharing
  one is a race by construction. All three spellings were broken and only one
  of them said so:

    for j := 1 to 3 do ...     j an enclosing local, so captured, so the worker
                               body became `for j^ := 1 to 3` -- which the
                               grammar refuses. `error: expected ':='`, reported
                               against lib/rtl/palthread.pas at a line number
                               from the user's file. That refusal was the only
                               thing protecting the program.
    j := 0; while j < 3 do     the same capture, spelled so the grammar allows
                               it. Compiled, and 100000x3 increments came back
                               299674 / 299015 / 295718 across runs.
    for g := 1 to 3 do ...     g a GLOBAL, so never captured. Compiled, and
                               HUNG: a worker resetting g to 1 keeps the other
                               workers' loops alive.

  The control variable of an inner `for` is now a worker-PRIVATE local whatever
  its storage was outside, which is what OpenMP does with loop variables inside
  a parallel region and the only reading under which those three rows agree.

  Rows here are exact totals, not approximations: a race shows up as a SHORT
  count, so 100000 outer iterations is the assertion. A variable a worker
  merely writes (the `while` shape) is still shared and still racy -- that
  needs an explicit clause and is
  feature-a-a-private-clause-for-parallel-for, not this.

  bug-a-a-nested-for-loop-in-a-parallel-for-body-is-a-compile-error }
program test_parallel_for_nested_for_body;
uses palparallel;

var g: Integer;                       { a GLOBAL inner control variable }

function Ascending(n: Integer): Int64;
var i, j: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for j := 1 to 3 do acc := acc + 1;
  end;
  Ascending := acc;
end;

function Descending(n: Integer): Int64;
var i, j: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for j := 3 downto 1 do acc := acc + 1;
  end;
  Descending := acc;
end;

function Global(n: Integer): Int64;
var i: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for g := 1 to 3 do acc := acc + 1;
  end;
  Global := acc;
end;

function Nested(n: Integer): Int64;
{ two levels, and the inner bound depends on the outer control variable --
  a shared `j` would make the inner trip count nondeterministic as well }
var i, j, k: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for j := 1 to 3 do
      for k := 1 to j do acc := acc + 1;
  end;
  Nested := acc;
end;

function Reused(n: Integer): Int64;
{ the same private name in two sibling loops, and a read of it AFTER the second
  -- the private must survive the first loop's exit }
var i, j: Integer; acc: Int64;
begin
  acc := 0;
  parallel(pdChunked) for i := 0 to n - 1 reduction(+: acc) do
  begin
    for j := 1 to 2 do acc := acc + 1;
    for j := 1 to 2 do acc := acc + 1;
    if j > 0 then acc := acc + 1;
  end;
  Reused := acc;
end;

begin
  WriteLn('asc   ', Ascending(100000));      { 300000 }
  WriteLn('desc  ', Descending(100000));     { 300000 }
  WriteLn('glob  ', Global(100000));         { 300000 }
  WriteLn('nest  ', Nested(100000));         { 6 per outer = 600000 }
  WriteLn('reuse ', Reused(100000));         { 5 per outer = 500000 }
  WriteLn('PARFOR NESTED FOR OK');
end.
