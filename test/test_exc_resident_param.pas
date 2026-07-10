{ SPDX-License-Identifier: 0BSD }
program TestExcResidentParam;
{ Regression: bug-a-o2-resident-param-stale-after-longjmp.

  r14/r15 regcall residency (-O2+) dual-writes param stores (frame slot +
  register cache), but the exception setjmp buf snapshots r12-r15 at try entry
  and the raise longjmp restores them — rolling the REGISTER back while the
  frame slot keeps the newer value. Handler reads then saw the stale snapshot.
  The fix reloads every resident register from its frame slot on the exception
  landing path, before any handler code runs.

  Exercises: one and two resident params, store-inside-try then raise, nested
  try (inner rethrow), and a loop that stores/raises repeatedly. All output
  must be identical at every -O level (test-opt differential membership). }

type
  EOops = class
  end;

function OneParam(x: Integer): Integer;
begin
  try
    x := 42;
    raise EOops.Create;
  except
    on e: EOops do
      OneParam := x;                 { must be 42, not the caller's value }
  end;
end;

function TwoParams(a, b: Integer): Integer;
begin
  try
    a := a + 100;                    { r14 store inside the protected block }
    b := b + 200;                    { r15 store inside the protected block }
    raise EOops.Create;
  except
    on e: EOops do
      TwoParams := a * 1000 + b;     { both must show the updated values }
  end;
end;

function NestedRethrow(x: Integer): Integer;
begin
  NestedRethrow := 0;
  try
    try
      x := 7;
      raise EOops.Create;
    except
      on e: EOops do
      begin
        x := x + 1;                  { store between the two landings }
        raise EOops.Create;          { outer landing must see x = 8 }
      end;
    end;
  except
    on e: EOops do
      NestedRethrow := x;
  end;
end;

function LoopStores(x: Integer): Integer;
var i, acc: Integer;
begin
  acc := 0;
  for i := 1 to 3 do
  begin
    try
      x := x + i;                    { resident store, then raise, per round }
      raise EOops.Create;
    except
      on e: EOops do
        acc := acc + x;              { must accumulate the updated x }
    end;
  end;
  LoopStores := acc;
end;

begin
  writeln('one:    ', OneParam(7));         { 42 }
  writeln('two:    ', TwoParams(1, 2));     { 101202 }
  writeln('nested: ', NestedRethrow(0));    { 8 }
  writeln('loop:   ', LoopStores(10));      { 11 + 13 + 16 = 40 }
end.
