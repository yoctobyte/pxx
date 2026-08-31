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
  for-loop iteration, and read-modify-write of the same captured array.

  Rows 7-10 are the rest of the acceptance list, added after the fact: the
  ELEMENT TYPE is not always Integer (a record, a Double, a Char and an
  AnsiString each move a different number of bytes, and the AnsiString rides
  the copy-in/copy-out as raw handles), an enclosing array PARAMETER is
  capturable as well as an enclosing local, and depth 2 is not depth 3.

  Row 6 (TwoArrays) is also the only row that calls a nested FUNCTION as a
  STATEMENT. That discards the result, and a discarded result spilled across
  the capture's copy-OUT is what i386 refused until 137f87025 — measured: a
  compiler with that one commit reverted rejects this file for --target=i386
  at TwoArrays and compiles it for x86-64. Which is why the cross rows in the
  Makefile are not decoration. }
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

type
  TPt = record X, Y: Integer; end;

function ElemKinds: Boolean;           { element types other than Integer }
var
  r: array[0..1] of TPt;
  d: array[0..1] of Double;
  c: array[0..2] of Char;
  s: array[0..1] of AnsiString;

  procedure Fill;
  begin
    r[0].X := 1; r[0].Y := 2; r[1].X := 3; r[1].Y := 4;
    d[0] := 1.5; d[1] := 2.25;
    c[0] := 'a'; c[1] := 'b'; c[2] := 'c';
    s[0] := 'hello'; s[1] := ' world';
  end;

begin
  Fill;
  ElemKinds := (r[0].X = 1) and (r[1].Y = 4)
           and (d[0] = 1.5) and (d[1] = 2.25)
           and (c[0] = 'a') and (c[2] = 'c')
           and (s[0] + s[1] = 'hello world');
end;

function Depth3: Integer;              { captured from THREE levels up }
var g: array[0..2] of Integer;
  procedure L1;
    procedure L2;
      procedure L3;
      begin g[2] := 42; end;
    begin L3; end;
  begin L2; end;
begin
  g[2] := 0; L1; Depth3 := g[2];
end;

function TakesArray(var g: TA): Integer;   { capture an enclosing PARAMETER }
  procedure Bump;
  var i: Integer;
  begin for i := 0 to 3 do g[i] := g[i] + 1; end;
begin
  Bump; Bump;
  TakesArray := g[0] + g[1] + g[2] + g[3];
end;

function ParamCapture: Boolean;
var a: TA;
    got: Integer;
begin
  a[0] := 100; a[1] := 101; a[2] := 102; a[3] := 103;
  got := TakesArray(a);
  { the writes must be visible in the CALLER's array, not just in the copy }
  ParamCapture := (got = 414) and (a[0] = 102) and (a[3] = 105);
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
  Chk(ElemKinds);
  Chk(Depth3 = 42);
  Chk(ParamCapture);
end.
