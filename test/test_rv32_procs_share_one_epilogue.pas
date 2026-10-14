program test_rv32_procs_share_one_epilogue;
{ On riscv32 --platform=esp every proc returns through ONE shared epilogue
  tail (`mv sp,s0; lw s0; lw ra; addi sp,16; ret`, emitted once ahead of the
  bodies), reached by a jal at the end of each body. Returns of every shape
  reach it: a plain result, an Int64 and a record result, an early Exit, a
  string local released on the way out, recursion, a method, a raise that
  unwinds through it, and an `iram;` routine, which keeps its own tail (an
  iram body must not jump into flash). Prints the same on x64. }
{$mode objfpc}
uses SysUtils;

type
  TPair = record
    a, b: LongInt;
  end;

  TCounter = class
    n: LongInt;
    function Bump(k: LongInt): LongInt; virtual;
  end;

  TCounter2 = class(TCounter)
    function Bump(k: LongInt): LongInt; override;
  end;

function TCounter.Bump(k: LongInt): LongInt;
begin
  n := n + k;
  Result := n;
end;

function TCounter2.Bump(k: LongInt): LongInt;
begin
  Result := inherited Bump(k * 2) + 1;
end;

function Add(a, b: LongInt): LongInt;
begin
  Result := a + b;
end;

function Big(a: LongInt): Int64;
begin
  Result := Int64(a) * 1000000007;
end;

function MakePair(x: LongInt): TPair;
begin
  Result.a := x;
  Result.b := -x;
end;

function FirstNeg(const v: array of LongInt): LongInt;
var i: LongInt;
begin
  for i := 0 to High(v) do
    if v[i] < 0 then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function Shout(const s: string; k: LongInt): string;
var t: string;
begin
  t := UpperCase(s);
  if k = 0 then Exit(t + '!');
  Result := t + IntToStr(k);
end;

function Fib(n: LongInt): LongInt;
begin
  if n < 2 then Exit(n);
  Result := Fib(n - 1) + Fib(n - 2);
end;

procedure Fail(k: LongInt);
var s: string;
begin
  s := 'bad ' + IntToStr(k);
  if k > 2 then
    raise Exception.Create(s);
end;

function Guarded(k: LongInt): LongInt;
begin
  Result := 0;
  try
    Fail(k);
    Result := k;
  except
    on e: Exception do Result := -Length(e.Message);
  end;
end;

function Twice(x: LongInt): LongInt; iram;
var i: LongInt;
begin
  Result := 0;
  for i := 1 to x do Result := Result + 2;
end;

var
  c: TCounter;
  p: TPair;
  i: LongInt;

begin
  writeln(Add(2, 40), ' ', Big(3), ' ', Big(-7));
  p := MakePair(11);
  writeln(p.a, ' ', p.b);
  writeln(FirstNeg([4, 5, -6, 7]), ' ', FirstNeg([1, 2]));
  writeln(Shout('hi', 0), ' ', Shout('yo', 3));
  writeln(Fib(15));
  for i := 1 to 4 do write(Guarded(i), ' ');
  writeln;
  c := TCounter2.Create;
  writeln(c.Bump(5), ' ', c.Bump(1));
  c.Free;
  writeln(Twice(21));
end.
