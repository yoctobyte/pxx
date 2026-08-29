{$mode objfpc}
program test_array_ctor_no_leak;

{ The CONSTRUCTOR twin of test_open_array_no_leak.

  `Take([...])` -- an array constructor in argument position -- built a heap
  dyn-array temp per call whose handle slot was re-nil'd on the next call,
  orphaning the previous block. The sibling arm (a fixed-array VARIABLE passed
  to the same parameter) was fixed in 2026-06 by replacing the heap temp with a
  frame-local [len][data] buffer; the constructor arm still allocated.

  ROW 3 IS THE ONE THAT MATTERS, and it is why this test is not just the
  sibling's with a different argument. The orphaned block OWNS what it points
  at, so a constructor of STRING elements leaks twice: the block, and every
  element handle the element-assign path ARC-retained into it. Measured
  pre-fix, 2M calls each:

      Take(['x'])              80.0 B/call        <- 1-char element
      Take(['x' * 32])        112.0 B/call
      Take(['x' * 128])       207.9 B/call        <- ~1 byte per character

  The element leak is PROPORTIONAL TO STRING LENGTH, so a probe built only from
  short literals cannot see it: a fix that released the block and not the
  elements would take row 1 from 80 to ~40 B/call and look like a success on
  every fixed-size row. Row 3's long element is what makes that failure visible
  -- it is the difference between a test that passes and a test that checks.

  Rows 1 and 2 are the counterparts of the ticket's own measurement table.
  Row 4 is the CONTROL: the same callee and parameter, an argument that is a
  named variable instead of a constructor. It was flat before the fix and must
  stay flat after -- a "fix" that made every row agree by making the variable
  case allocate would pass a slope test on the leaking rows alone.

  Output: "ok 4000000". }

const
  LONG = 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' +
         'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

var
  calls: Integer;

procedure TakeS(const a: array of AnsiString);
var i, n: Integer;
begin
  n := 0;
  for i := 0 to High(a) do n := n + Length(a[i]);
  if n < 0 then writeln('impossible');
  Inc(calls);
end;

procedure TakeI(const a: array of Integer);
var i, n: Integer;
begin
  n := 0;
  for i := 0 to High(a) do n := n + a[i];
  if n < 0 then writeln('impossible');
  Inc(calls);
end;

var
  av: array[0..1] of AnsiString;
  k: Integer;
begin
  calls := 0;
  av[0] := 'aa'; av[1] := 'bb';
  for k := 1 to 1000000 do
  begin
    TakeI([1, 2]);        { row 1: the block only -- unmanaged elements }
    TakeS(['x', 'y']);    { row 2: block + two short element handles }
    TakeS([LONG]);        { row 3: block + one 128-char element -- the length-proportional leak }
    TakeS(av);            { row 4: CONTROL -- a variable, must stay flat }
  end;
  writeln('ok ', calls);
end.
