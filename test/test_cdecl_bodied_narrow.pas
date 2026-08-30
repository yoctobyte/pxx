program test_cdecl_bodied_narrow;
{ Bodied `cdecl` procs with signatures narrow enough for EVERY target.

  bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets

  THE THIRD cdecl FILE, AND THE SPLIT IS AN ABI BOUNDARY, NOT TIDINESS:
    test_cdecl_bodied_sysv.pas   - x86-64 only; assignment shape, >6 params,
                                   9-argument overflow cases.
    test_cdecl_bodied_cross.pas  - x86-64 + aarch64; up to 8 args per bank.
    this file                    - every target, argument block <= 4 machine
                                   words, because arm32 (armel soft-float)
                                   refuses more and stack arguments are
                                   unimplemented on both sides of the call
                                   there. See
                                   bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area.
  A test file that cannot COMPILE for a target asserts nothing about it, so the
  narrowest common signature set lives here rather than being bolted onto a file
  the narrow target must skip.

  THE DISCRIMINATING CASE FOR arm32 IS `Integer FIRST, Double SECOND`, and it is
  NOT the case that discriminated the other two targets. armel is SOFT-FLOAT:
  doubles travel in the CORE registers r0..r3, so the "independent int and float
  banks" divergence that broke x86-64 and aarch64 does not exist here. What
  exists is an ALIGNMENT rule -- an 8-byte by-value param must start at an even
  word index, so (Integer, Double) puts the double in r2:r3 and SKIPS r1, while
  a positional convention packs it into r1:r2.

  Measured before arm32's arm existed: `f(a: Double; b: Integer)` printed the
  RIGHT answer (soft-float coincides with positional when the double is first),
  and `f(a: Integer; b: Double)` printed 7 where 9 was correct, the double
  arriving as zero. Reusing another target's discriminating case here would have
  reported a false green from a correct test pointed at the wrong ABI. Both
  orders are therefore asserted below, deliberately. }

type
  TFnDI = function(a: Double; b: Integer): Integer; cdecl;
  TFnID = function(a: Integer; b: Double): Integer; cdecl;
  TFnSI = function(s: Single; n: Integer): Integer; cdecl;
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

function CbDI(a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;

{ The alignment case. On arm32 this is the ONLY one of the four that fails
  without an AAPCS prologue. }
function CbID(a: Integer; b: Double): Integer; cdecl;
begin Result := a + Trunc(b); end;

function CbSI(s: Single; n: Integer): Integer; cdecl;
begin Result := Trunc(s * 2) + n; end;

{ A by-REF float is a POINTER: one word, integer class, no 8-byte alignment
  demand. Sized as a double it desynchronises the block and segfaults -- the
  same predicate, wrong on all four targets, with four different symptoms.
  bug-a-a-by-ref-float-param-through-a-cdecl-fnptr-is-classified-sse }
function CbRef(var a: Double; b: Integer): Integer; cdecl;
begin Result := Trunc(a) + b; end;

procedure TakeDI(fn: TFnDI);
begin Expect(fn(2.5, 7), 9, 'double-then-int via fnptr'); end;

procedure TakeID(fn: TFnID);
begin Expect(fn(7, 2.0), 9, 'int-then-double via fnptr (8-byte alignment)'); end;

procedure TakeSI(fn: TFnSI);
begin Expect(fn(1.5, 4), 7, 'single-then-int via fnptr'); end;

procedure TakeRef(fn: TFnRef);
var d: Double;
begin
  d := 2.5;
  Expect(fn(d, 7), 9, 'by-ref float via fnptr');
end;

{ The ASSIGNMENT shape. Refused outright on a target still behind the ir.inc
  reject, so this half does not COMPILE there -- which is what stops this file
  being wired for a target before that target is ready. All three targets wired
  today (x86-64, aarch64, arm32) have their arm AND have left the reject. }
procedure ViaVariable;
var f: TFnID;
begin
  f := @CbID;
  Expect(f(7, 2.0), 9, 'int-then-double via assigned variable');
end;

var dref: Double;
begin
  TakeDI(@CbDI);
  TakeID(@CbID);
  TakeSI(@CbSI);
  TakeRef(@CbRef);

  Expect(CbDI(2.5, 7), 9, 'double-then-int direct');
  Expect(CbID(7, 2.0), 9, 'int-then-double direct');
  Expect(CbSI(1.5, 4), 7, 'single-then-int direct');
  dref := 2.5;
  Expect(CbRef(dref, 7), 9, 'by-ref float direct');
  ViaVariable;

  if failures = 0 then
    writeln('CDECL-NARROW OK checks=', checks)
  else
    writeln('CDECL-NARROW FAILURES=', failures);
end.
