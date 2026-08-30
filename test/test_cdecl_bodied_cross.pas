program test_cdecl_bodied_cross;
{ A bodied `cdecl` proc receives the C convention, on every target that claims to
  support it. Cross-target sibling of test_cdecl_bodied_sysv.pas.

  bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets

  WHY A SEPARATE FILE rather than more rows in the x86-64 one: that file's
  overflow case passes NINE arguments, and aarch64's indirect-call path refuses
  more than eight -- an honest refusal on both sides of the call, not a bug. A
  test file that cannot COMPILE for a target cannot assert anything about it, so
  the cross-target cases live here and stay inside 8 arguments per bank.

  BOTH SHAPES ARE ASSERTED, and a target is wired into this file only once it
  has BOTH its prologue arm AND has left the ir.inc reject -- in that order. The
  assignment shape (`p := @Cb`) is still refused on i386/arm32/riscv32, and that
  refusal is correct: it is the wall that keeps them sound while they have no
  arm. The argument shape is the one that always escaped the reject, which is
  why it was the silently-wrong one.

  THE DISCRIMINATING CASE IS Mixed. AAPCS64 and SysV both count the integer and
  floating banks INDEPENDENTLY: f(i1,d1,i2,d2,i3,d3) puts i1,i2,i3 in the first
  three integer registers and d1,d2,d3 in the first three FP registers. The
  positional convention a bodied proc used to receive puts them in integer
  registers 0..5 by ordinal, so the two disagree about every parameter after the
  first. An all-int or all-float signature cannot tell those apart. }

type
  TFn2   = function(a: Double; b: Integer): Integer; cdecl;
  TFnMix = function(i1: Integer; d1: Double; i2: Integer; d2: Double;
                    i3: Integer; d3: Double): Integer; cdecl;
  TFnSng = function(s: Single; n: Integer): Integer; cdecl;
  TFnRef = function(var a: Double; b: Integer): Integer; cdecl;

var failures: Integer = 0;
    checks: Integer = 0;

procedure Expect(got, want: Integer; const nm: AnsiString);
begin
  Inc(checks);
  if got <> want then
  begin
    writeln('FAIL ', nm, ': got ', got, ' want ', want);
    Inc(failures);
  end;
end;

function CbFloat(a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;

function CbMix(i1: Integer; d1: Double; i2: Integer; d2: Double;
               i3: Integer; d3: Double): Integer; cdecl;
begin
  Result := i1 + i2*10 + i3*100 + Trunc(d1)*1000 + Trunc(d2)*10000 + Trunc(d3)*100000;
end;

function CbSingle(s: Single; n: Integer): Integer; cdecl;
begin Result := Trunc(s * 2) + n; end;

{ A by-REF float is a POINTER and belongs to the INTEGER bank on both sides.
  Getting it wrong is a SEGFAULT, not a wrong number, and it was wrong on x86-64
  in both directions at once for a while.
  bug-a-a-by-ref-float-param-through-a-cdecl-fnptr-is-classified-sse }
function CbByRef(var a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;

procedure TakeFloat(fn: TFn2);
begin Expect(fn(2.5, 7), 9, 'float arg via fnptr'); end;

procedure TakeMix(fn: TFnMix);
begin Expect(fn(1, 4.0, 2, 5.0, 3, 6.0), 654321, 'mixed int/float banks via fnptr'); end;

procedure TakeSng(fn: TFnSng);
begin Expect(fn(1.5, 4), 7, 'single arg via fnptr'); end;

procedure TakeRef(fn: TFnRef);
var d: Double;
begin
  d := 2.5;
  Expect(fn(d, 7), 9, 'by-ref float arg via fnptr');
end;

{ The ASSIGNMENT shape. Refused outright on a target that has not left the
  reject, so this half does not COMPILE there -- which is the point: it is what
  stops this file being wired for a target before that target is ready. }
procedure ViaVariable;
var f: TFnMix;
begin
  f := @CbMix;
  Expect(f(1, 4.0, 2, 5.0, 3, 6.0), 654321, 'mixed via assigned variable');
end;

var dref: Double;
begin
  TakeFloat(@CbFloat);
  TakeMix(@CbMix);
  TakeSng(@CbSingle);
  TakeRef(@CbByRef);

  { and directly, which must agree with the same prologue }
  Expect(CbFloat(2.5, 7), 9, 'float direct');
  Expect(CbMix(1, 4.0, 2, 5.0, 3, 6.0), 654321, 'mixed direct');
  Expect(CbSingle(1.5, 4), 7, 'single direct');
  dref := 2.5;
  Expect(CbByRef(dref, 7), 9, 'by-ref float direct');
  ViaVariable;

  if failures = 0 then
    writeln('CDECL-CROSS OK checks=', checks)
  else
    writeln('CDECL-CROSS FAILURES=', failures);
end.
