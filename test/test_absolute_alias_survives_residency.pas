program test_absolute_alias_survives_residency;
{ An `absolute` overlay is the ONE alias in the language that takes no address:
  two symbol indices name one frame slot, and no IR_LEA / IR_SLOTADDR is ever
  emitted for either. Six separate guards — the -O2 parameter residency, the
  -O3 unified residency and its aarch64 twin, the argument-deferral cache, the
  per-proc addr-taken-param summary, the --measure-regcall probe — each asked
  "is this symbol's address taken in this body" with their own copy of the same
  scan, so every one of them answered "clean" and the optimizer was free to keep
  a cached copy of a slot the overlay wrote behind its back.

  Measured before the fix, on ByValueScalar below: correct at -O0 and -O1, and
  from -O2 up the parameter was loaded into r14 at entry and read back from
  there, so the byte written through `w` never reached it.

  This test's property is therefore NOT "the value is 16909061" — the other
  absolute test asserts that. It is that the answer does not DEPEND on the
  optimisation level, so the Makefile compiles it at -O0 and at -O3 and requires
  the same output. -O0 is the reference (no residency runs at all) and -O3 turns
  on the loop-residency pass as well, which claims LOCALS and not just params.
  bug-a-an-absolute-overlay-of-a-by-value-parameter-is-lost }
{$mode objfpc}{$H+}

{ a by-VALUE parameter, written through a scalar overlay and then read back —
  the shape the -O2 param residency cached }
function ByValueScalar(v: Integer): Integer;
var w: Byte absolute v;
begin w := 5; ByValueScalar := v; end;

{ the same through an ARRAY overlay }
function ByValueArr(v: Integer): Integer;
var b: array[0..3] of Byte absolute v;
begin b[0] := 5; ByValueArr := v; end;

{ the overlay written on ONE side of a branch: the read after the join must not
  come from a register loaded before it }
function ByValueCond(v: Integer; doIt: Boolean): Integer;
var w: Byte absolute v;
begin if doIt then w := 5; ByValueCond := v; end;

{ a LOCAL overlay target read hot inside a loop — what -O3 unified residency
  ranks and claims; the write through b[0] happens mid-loop }
function LocalHot: Integer;
var i, k, acc: Integer;
    b: array[0..3] of Byte absolute i;
begin
  i := $01020304; acc := 0;
  for k := 1 to 10 do
  begin
    acc := acc + i + i + i + i;
    if k = 5 then b[0] := 5;
  end;
  LocalHot := acc;
end;

{ the reverse direction: the OVERLAY is the hot symbol and the TARGET is
  written, so the flag has to be recorded on both sides of the alias }
function OverlayHot: Integer;
var i, k, acc: Integer;
    b: array[0..3] of Byte absolute i;
begin
  i := $01020304; acc := 0;
  for k := 1 to 10 do
  begin
    acc := acc + b[0] + b[0] + b[0] + b[0];
    if k = 5 then i := $01020309;
  end;
  OverlayHot := acc;
end;

{ a by-value param whose overlay is written between two reads, with a CALL in
  between — the argument-deferral cache is the sixth guard }
function Ident(x: Integer): Integer;
begin Ident := x; end;

function ByValueAcrossCall(v: Integer): Integer;
var w: Byte absolute v;
    a, b: Integer;
begin
  a := Ident(v);
  w := 5;
  b := Ident(v);
  ByValueAcrossCall := a + b;
end;

begin
  WriteLn('scalar   ', ByValueScalar($01020304));
  WriteLn('array    ', ByValueArr($01020304));
  WriteLn('cond-yes ', ByValueCond($01020304, True));
  WriteLn('cond-no  ', ByValueCond($01020304, False));
  WriteLn('localhot ', LocalHot);
  WriteLn('ovlhot   ', OverlayHot);
  WriteLn('acrcall  ', ByValueAcrossCall($01020304));
end.
