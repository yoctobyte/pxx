{ Nested routine capturing a FIXED-SIZE array local of an enclosing routine.

  Until feature-nested-routine-fixed-array-capture this was refused outright
  ("capture of fixed-size array 'g' not yet supported") and callers flattened
  the helper by hand -- see DnsParseIpv6 in lib/rtl/dns_config.pas, which is
  where the gap was found.

  A fixed array differs from a dynamic one here in the one way that matters:
  a dyn array is self-describing at runtime, while a fixed one carries its
  extent only in its TYPE, and the enclosing symbol is recycled before the
  lifted body is parsed. So the shape is snapshotted at capture and replayed
  onto the lifted `var` param (LiftCapFixedLen/LiftCapFixedLo).

  Row 1 is the one that fails LOUDEST if the low bound is dropped: without it
  IR_INDEX subtracts 0 and `g[1]` of an `array[1..3]` writes the next element,
  which is silent. Rows 3-5 are the acceptance list: whole-array pass-through,
  for-loop iteration, and read-modify-write of the same captured array. }
program test_nested_fixed_array_capture;

type TA = array[0..3] of Integer;

function LowBound: Boolean;            { non-zero low bound }
var g: array[1..3] of Integer;
  procedure Put(i, v: Integer);
  begin g[i] := v; end;
begin
  g[1] := 0; g[2] := 0; g[3] := 0;
  Put(1, 7); Put(2, 8); Put(3, 9);
  LowBound := (g[1] = 7) and (g[2] = 8) and (g[3] = 9);
end;

function Depth2: Integer;              { captured from two levels up }
var g: array[0..3] of Integer;
  procedure Mid;
    procedure Inner;
    begin g[2] := 55; end;
  begin Inner; end;
begin
  g[2] := 0; Mid; Depth2 := g[2];
end;

function Sum(const a: TA): Integer;
var i, s: Integer;
begin s := 0; for i := 0 to 3 do s := s + a[i]; Sum := s; end;

function WholeArray: Integer;          { pass the captured array to a further call }
var g: TA;
  function Go: Integer;
  begin Go := Sum(g); end;
begin
  g[0] := 1; g[1] := 2; g[2] := 3; g[3] := 4;
  WholeArray := Go;
end;

function IterateIt: Integer;           { for-loop over the captured array }
var g: array[0..4] of Integer;
  function Total: Integer;
  var i, s: Integer;
  begin s := 0; for i := 0 to 4 do s := s + g[i]; Total := s; end;
var i: Integer;
begin
  for i := 0 to 4 do g[i] := i * 10;
  IterateIt := Total;
end;

function ReadWrite: Integer;           { read AND write the same captured array }
var g: array[0..2] of Integer;
  procedure Bump;
  begin g[0] := g[0] + 1; g[1] := g[0] * 2; end;
begin
  g[0] := 5; g[1] := 0; g[2] := 0;
  Bump; Bump;
  ReadWrite := g[0] * 100 + g[1];
end;

function TwoArrays: Boolean;           { the shape the ticket was filed from }
var leftG, rightG: array[0..7] of Integer;
    leftN, rightN: Integer;
    onRight: Boolean;

  function AddGroup(v: Integer): Boolean;
  begin
    AddGroup := False;
    if leftN + rightN >= 8 then Exit;
    if onRight then begin rightG[rightN] := v; rightN := rightN + 1; end
    else begin leftG[leftN] := v; leftN := leftN + 1; end;
    AddGroup := True;
  end;

begin
  leftN := 0; rightN := 0; onRight := False;
  AddGroup(1); AddGroup(2);
  onRight := True;
  AddGroup(9);
  TwoArrays := (leftG[0] = 1) and (leftG[1] = 2) and (rightG[0] = 9)
               and (leftN = 2) and (rightN = 1);
end;

procedure Chk(c: Boolean);
begin
  if c then writeln('1') else writeln('0');
end;

begin
  Chk(LowBound);
  Chk(Depth2 = 55);
  Chk(WholeArray = 10);
  Chk(IterateIt = 100);
  Chk(ReadWrite = 714);
  Chk(TwoArrays);
end.
