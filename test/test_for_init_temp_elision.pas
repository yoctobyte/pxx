program ForInitTempElision;
{ feature-opt-o3-register-pressure: at -O3 the AN_FOR hidden INIT temp is elided
  when both bounds are re-emittable (literal / plain scalar variable / pure
  arithmetic over those). The temp exists so that the initial expression is
  evaluated BEFORE the limit and before the control variable is assigned
  (bug-a-for-loop-limit-is-evaluated-after-the-control-variable-is-assigned); it
  costs a store plus a load at every loop ENTRY, measured at exactly 2
  instructions per entry.

  Eliding it means the initial bound is re-emitted at the store, i.e. AFTER the
  limit's code has run. Every row below is a shape where that reordering is
  observable if the reasoning is wrong, so this is the file that catches a
  reintroduction of the original silent wrong-iteration-count bug:

    - a bound that MENTIONS THE CONTROL VARIABLE, on either side or both. These
      are the exact shapes the original bug got wrong, and they are elided now,
      so they are the sharpest rows here.
    - `for n := n - 3 to n`: the initial bound reads n and the limit reads n, and
      neither may see the store. If the elision let the store happen first, or
      let the limit's capture change what the initial bound reads, the count
      changes.
    - downto, which had its own wrong answer (9 against FPC's 3).
    - a NON-elided control in the same program: a bound containing a CALL is
      still captured, so if the elision ever widened to calls by accident these
      rows would move while the others stayed put.

  Counts verified against FPC 3.2.2. Run at -O0 and -O3 against one expectation:
  the elision is -O3-gated, so -O0 is a control that provably still captures. }

var
  gLog: AnsiString;
  gCalls: LongInt;

function Bump(tag: AnsiString; v: LongInt): LongInt;
begin
  { The log makes call ORDER observable. A count alone does not: eliding a
    call-bearing initial bound swaps the two calls, and both orders make the
    same number of calls and the same iteration count, so gCalls and the count
    are both blind to it. Found by breaking the elision on purpose and watching
    this row keep passing. }
  gLog := gLog + tag;
  gCalls := gCalls + 1;
  Bump := v;
end;

function CountPlain: LongInt;
var n, i, c: LongInt;
begin
  c := 0;
  n := 5;
  for n := 1 to n do c := c + 1;          { init literal, limit reads n }
  CountPlain := c;
end;

function CountIdentBounds: LongInt;
var lo, hi, i, c: LongInt;
begin
  c := 0; lo := 3; hi := 7;
  for i := lo to hi do c := c + 1;        { both plain idents -- ELIDED }
  CountIdentBounds := c;
end;

function CountSelfInit: LongInt;
var n, c: LongInt;
begin
  c := 0; n := 3;
  for n := n to 5 do c := c + 1;          { init reads n -- ELIDED }
  CountSelfInit := c;
end;

function CountSelfBoth: LongInt;
var n, c: LongInt;
begin
  c := 0; n := 5;
  for n := n to n do c := c + 1;          { both read n -- ELIDED }
  CountSelfBoth := c;
end;

function CountArithSelf: LongInt;
var n, c: LongInt;
begin
  c := 0; n := 5;
  for n := n - 3 to n do c := c + 1;      { pure arithmetic both sides -- ELIDED }
  CountArithSelf := c;
end;

function CountDownSelf: LongInt;
var n, c: LongInt;
begin
  c := 0; n := 9;
  for n := n downto n - 6 do c := c + 1;  { downto, both read n -- ELIDED }
  CountDownSelf := c;
end;

function CountCallBound: LongInt;
var n, c: LongInt;
begin
  c := 0; n := 4;
  gCalls := 0; gLog := '';
  for n := Bump('i', 2) to Bump('L', n) do c := c + 1;  { calls -- NOT elided }
  CountCallBound := c * 100 + gCalls;
end;

begin
  WriteLn('plain=', CountPlain);
  WriteLn('ident=', CountIdentBounds);
  WriteLn('selfinit=', CountSelfInit);
  WriteLn('selfboth=', CountSelfBoth);
  WriteLn('arithself=', CountArithSelf);
  WriteLn('downself=', CountDownSelf);
  WriteLn('callbound=', CountCallBound);
  { Pascal evaluates the initial expression before the final one, so this must
    read 'iL'. Unconditional elision makes it 'Li' -- the assertion that a count
    cannot make. }
  WriteLn('callorder=', gLog);
  WriteLn('done');
end.
