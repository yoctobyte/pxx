program test_cdecl_bodied_sysv;
{ A bodied `cdecl` proc must receive genuine SysV, and its call sites must agree.

  feature-cdecl-bodied-sysv-prologue
  bug-a-a-cdecl-procaddr-passed-as-an-argument-escapes-the-sysv-soundness-reject

  Before this landed, a bodied cdecl proc got the INTERNAL convention (every
  param in a GP register by position, >6 all-stack) while every cdecl CALL site
  marshalled true SysV. The two coincide only for <=6 integer/pointer params, so
  the whole family below was wrong and SILENT: `Take(@MyCb)` printed 4261032
  where 9 is correct.

  ir.inc rejects the unsound binding -- but only in the ASSIGNMENT shape
  (AN_ASSIGN whose RHS is AN_PROCADDR). Every case here uses the ARGUMENT shape,
  which is the shape that escaped the reject, so this file is exercising the
  door in the wall rather than the wall.

  THE DISCRIMINATING CASE IS Mixed, not the float one. SysV counts the integer
  and SSE classes INDEPENDENTLY: in f(i1, d1, i2, d2, i3, d3) the ints take
  rdi/rsi/rdx and the doubles take xmm0/xmm1/xmm2. Position-based homing puts
  them in rdi..r9 by ordinal instead, so the two disagree about every parameter
  after the first. A test built only from all-float or all-int signatures cannot
  tell a correct independent-counter implementation from an implementation that
  merely shifted everything by a fixed amount. }

type
  TFn2   = function(a: Double; b: Integer): Integer; cdecl;
  TFn8   = function(a, b, c, d, e, f, g, h: Integer): Integer; cdecl;
  TFnMix = function(i1: Integer; d1: Double; i2: Integer; d2: Double;
                    i3: Integer; d3: Double): Integer; cdecl;
  TFnSng = function(s: Single; n: Integer): Integer; cdecl;
  TFnOvf = function(a, b, c, d, e, f, g: Integer; x, y: Double): Integer; cdecl;

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
begin
  Result := Trunc(a) + b;
end;

function Cb8(a, b, c, d, e, f, g, h: Integer): Integer; cdecl;
begin
  Result := a + b*2 + c*3 + d*4 + e*5 + f*6 + g*7 + h*8;
end;

{ Independent class counters: each param is weighted by a distinct prime-ish
  factor so ANY permutation between the two banks changes the total. }
function CbMix(i1: Integer; d1: Double; i2: Integer; d2: Double;
               i3: Integer; d3: Double): Integer; cdecl;
begin
  Result := i1 + i2*10 + i3*100 + Trunc(d1)*1000 + Trunc(d2)*10000 + Trunc(d3)*100000;
end;

function CbSingle(s: Single; n: Integer): Integer; cdecl;
begin
  Result := Trunc(s * 2) + n;
end;

{ 7 ints and 2 doubles: the 7th int spills to the stack while both doubles are
  still in xmm0/xmm1 -- one class overflowing while the other has not is the
  case a single shared counter gets wrong. }
function CbOverflow(a, b, c, d, e, f, g: Integer; x, y: Double): Integer; cdecl;
begin
  Result := a + b + c + d + e + f + g + Trunc(x)*1000 + Trunc(y)*10000;
end;

{ Taking the parameter as a value forces the ARGUMENT shape, which is the one
  the ir.inc reject does not cover. }
procedure TakeFloat(fn: TFn2);
begin Expect(fn(2.5, 7), 9, 'float arg via fnptr'); end;

procedure Take8(fn: TFn8);
begin Expect(fn(1,2,3,4,5,6,7,8), 204, '8 int args via fnptr'); end;

procedure TakeMix(fn: TFnMix);
begin Expect(fn(1, 4.0, 2, 5.0, 3, 6.0), 654321, 'mixed int/float classes via fnptr'); end;

procedure TakeSng(fn: TFnSng);
begin Expect(fn(1.5, 4), 7, 'single arg via fnptr'); end;

procedure TakeOvf(fn: TFnOvf);
begin Expect(fn(1,2,3,4,5,6,7, 8.0, 9.0), 98028, 'int overflow with floats in regs'); end;

begin
  { via a function pointer -- the escaping shape }
  TakeFloat(@CbFloat);
  Take8(@Cb8);
  TakeMix(@CbMix);
  TakeSng(@CbSingle);
  TakeOvf(@CbOverflow);

  { and DIRECTLY, which must keep agreeing with the same prologue }
  Expect(CbFloat(2.5, 7), 9, 'float direct');
  Expect(Cb8(1,2,3,4,5,6,7,8), 204, '8 int direct');
  Expect(CbMix(1, 4.0, 2, 5.0, 3, 6.0), 654321, 'mixed direct');
  Expect(CbSingle(1.5, 4), 7, 'single direct');
  Expect(CbOverflow(1,2,3,4,5,6,7, 8.0, 9.0), 98028, 'overflow direct');

  if failures = 0 then
    writeln('CDECL-SYSV OK checks=', checks)
  else
    writeln('CDECL-SYSV FAILURES=', failures);
end.
