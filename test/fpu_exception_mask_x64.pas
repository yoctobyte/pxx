program fpu_exception_mask_x64;
{ GetExceptionMask / SetExceptionMask — the FPC Math-unit float-exception
  surface (feature-b-fpc-exception-mask-api-in-math).

  NAMED OUTSIDE the lib_*.pas glob on purpose: tools/lib_cross_sweep.sh builds
  every test/lib_*.pas for i386/arm32/aarch64/riscv32, and this API is x86-64
  only BY DESIGN — the intrinsics behind it are a compile-time Error elsewhere,
  because those targets have no architecturally guaranteed trap enable. A test
  that cannot build on four of five targets would read as a sweep failure
  rather than as the refusal it is, so it stays out of the sweep's sight and is
  wired into lib-test directly.

  What is checked is what the ticket's gate asks for: a mask round-trips, and
  the DEFAULT is untouched. pxx starts with every exception masked (quiet IEEE,
  user decision 2026-07-02) — FPC starts with invalid/zero-divide/overflow
  UNmasked, and that difference is deliberate on both sides.

  Not checked here: that clearing a bit actually traps. It does (SIGFPE, and
  __pxxSigCode names the cause), but a test whose success condition is a fatal
  signal belongs in the compiler suite, where test_float_exception_mask.pas
  already has it. }
uses math;

var failures: Integer;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok')
  else begin writeln(tag, '=FAIL'); failures := failures + 1; end;
end;

var
  start, prev, cur: TFPUExceptionMask;
  e: TFPUException;
  n: Integer;
begin
  failures := 0;
  start := GetExceptionMask;

  { the default is quiet IEEE: all six masked, so nothing traps }
  n := 0;
  for e := Low(TFPUException) to High(TFPUException) do
    if e in start then n := n + 1;
  SayBool('default-all-masked', n = 6);
  SayBool('default-invalid', exInvalidOp in start);
  SayBool('default-zerodiv', exZeroDivide in start);

  { SetExceptionMask returns the PREVIOUS mask, not the new one — measured
    against FPC 3.2.2, and the opposite of the obvious guess. Save/restore
    depends on it. }
  prev := SetExceptionMask([exInvalidOp, exZeroDivide]);
  SayBool('set-returns-previous', prev = start);

  cur := GetExceptionMask;
  SayBool('set-took-effect', cur = [exInvalidOp, exZeroDivide]);
  SayBool('set-cleared-others', not (exOverflow in cur));

  { every bit is reachable, in both directions: the set<->bitmask conversion is
    the whole of this API, so an off-by-one in the enum order would show here }
  for e := Low(TFPUException) to High(TFPUException) do
  begin
    SetExceptionMask([e]);
    cur := GetExceptionMask;
    SayBool('single-' + Chr(Ord('0') + Ord(e)), cur = [e]);
  end;

  SetExceptionMask([]);
  SayBool('empty', GetExceptionMask = []);

  prev := SetExceptionMask(start);
  SayBool('restore-returns-empty', prev = []);
  SayBool('restored', GetExceptionMask = start);

  if failures = 0 then writeln('fpu_exception_mask: all ok')
  else writeln('fpu_exception_mask: ', failures, ' FAIL');
end.
