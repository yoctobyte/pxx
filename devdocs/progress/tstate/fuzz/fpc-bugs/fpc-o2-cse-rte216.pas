{ FPC 3.2.2 x86_64-linux: -O2/-O3 miscompiles this program into a
  Runtime error 216 (general protection fault). -O1, -O-, and -O2 with any of
  the individual optimizer passes disabled all run cleanly. The source is
  memory-safe: every array index is a constant in range, no pointers, no
  uninitialized reads. Reduced from a random Object Pascal generator (pasmith).
  Marker writeln prints when the program survives; under -O2 it never reaches it. }
{$mode objfpc}
type
  TE0 = (e0_0, e0_1);
  TE1 = (e1_0, e1_1, e1_2, e1_3, e1_4);
  TR0I = record r0i0: longint; end;
  TR0 = record r0n: TR0I; r0a: array[0..3] of longint; end;
  TR1 = packed record r1f0: smallint; end;
var
  g3: word; g5: longword; g12: word; g17: boolean; g19: byte;
  r0g: TR0; r1g: TR1;
  ar0: array[0..3] of longint;
  ar1: array[0..3] of longint;
  ev0: TE0; ev1: TE1;

function SafeDiv_word(a, b: word): word;    begin SafeDiv_word := a; end;
function SafeDiv_longint(a, b: longint): longint; begin SafeDiv_longint := a; end;
function SafeMod_longint(a, b: longint): longint; begin SafeMod_longint := a; end;

function f0(p0: smallint; p1: byte; p2: longword): longint;
var v4: longint;
begin
  v4 := p0;
  case longint(longint(longint(-v4) xor longint(v4 - v4))) and 3 of
    0: begin end;
  else
    case longint(v4) and 3 of 0: begin end; end;
  end;
  f0 := v4;
end;

begin
  g3 := 0; g5 := 0; g12 := 0; g17 := false; g19 := 0;
  ev0 := e0_0; ev1 := e1_0;
  FillChar(r0g, SizeOf(r0g), 0);
  FillChar(r1g, SizeOf(r1g), 0);
  FillChar(ar0, SizeOf(ar0), 0);
  FillChar(ar1, SizeOf(ar1), 0);

  if g17 then
  begin end
  else
  begin
    case longint(longint(longint(r0g.r0a[2] * ord(ev0)) - f0(r1g.r1f0, g19, g5))) and 3 of
      0: begin
        g17 := (g12 = word(word(g12 and g3) or SafeDiv_word(word(g12), word(g12))));
      end;
    end;
    case longint(SafeDiv_longint(longint(ord(ev1)), longint(SafeMod_longint(longint(r0g.r0n.r0i0), longint(r0g.r0a[0]))))) and 3 of
      0: begin end;
    end;
  end;
  case longint(ar0[1]) and 3 of 0: begin end; end;
  case longint(ar1[0]) and 3 of 0: begin end; end;
  case longint(SafeMod_longint(longint(SafeDiv_longint(longint(r0g.r0n.r0i0), longint(r0g.r0a[1]))), longint(longint(longint(ar0[0]) shr (longint(ar0[3]) and 31))))) and 3 of
    0: begin
      ar0[2] := longint(ord(((g17 or g17) or (ar0[2] > ar1[0]))));   { <-- RTE 216 here under -O2 }
      case longint(ar1[2]) and 3 of 0: begin end; end;
      case longint(SafeDiv_longint(longint(longint(-ar1[3])), longint(r0g.r0a[0]))) and 3 of
        0: begin end;
      end;
    end;
  end;
  writeln('survived');
end.
