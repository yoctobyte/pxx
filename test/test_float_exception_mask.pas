program test_float_exception_mask;
{ Float-exception MASK control (feature-float-exception-mask-control).

  pxx's default is quiet IEEE — 1/0 is +Inf, 0/0 is NaN, overflow is Inf, and
  they propagate — and that is a decision, not an accident (user, 2026-07-02:
  measurement/streaming data with out-of-bounds inputs is better served by
  propagation than by aborting mid-computation). FPC unmasks at startup and
  turns those into runtime errors 205/206/207/208; this file is the mechanism
  that makes emulating FPC POSSIBLE without making it the default.

  `__pxxSetFPUMask(m)` returns the PREVIOUS mask, so save/restore is one
  expression. The value is a 6-bit set in FPC's TFPUException order — bit 0
  exInvalidOp, 1 exDenormalized, 2 exZeroDivide, 3 exOverflow, 4 exUnderflow,
  5 exPrecision — with 1 = masked. All six masked is 63, which is the default
  and is asserted here.

  The trap path is checked by CAUSE, because that is the whole point: which
  runtime error FPC reports depends on which exception fired, and si_code is
  the only carrier of that (the MXCSR status flags read 0x00 inside a handler
  — Linux hands it a clean FP state; measured, see the ticket).

  Note what the handler must NOT do: re-masking MXCSR inside the handler does
  not help it return, because sigreturn RESTORES the FP state from the
  ucontext and the faulting instruction then traps again, forever. Recovery
  goes through the saved PC (__pxxSigPCPtr) exactly as it does for SIGSEGV. }

type
  PPtrUInt = ^PtrUInt;

const
  ALL_MASKED  = 63;
  M_INVALID   = 1;
  M_ZERODIV   = 4;
  M_OVERFLOW  = 8;
  M_UNDERFLOW = 16;
  M_PRECISION = 32;

  FPE_FLTDIV = 3;
  FPE_FLTOVF = 4;
  FPE_FLTUND = 5;
  FPE_FLTRES = 6;
  FPE_FLTINV = 7;

var
  a, b, r: Double;
  old, lastCode: Integer;

procedure Raiser;
begin
  raise 205;
end;

procedure OnFPE;
begin
  lastCode := __pxxSigCode;
  { Redirect rather than return: returning would re-run the faulting SSE
    instruction with the kernel-restored (still unmasked) MXCSR. }
  PPtrUInt(__pxxSigPCPtr)^ := PtrUInt(@Raiser);
end;

{ Unmask one cause, run the operation, and report which exception fired. }
procedure Trap(clear: Integer; kind: Integer);
var keep: Integer;
begin
  lastCode := -1;
  keep := __pxxSetFPUMask(ALL_MASKED and not clear);
  try
    case kind of
      0: begin a := 1.0; b := 0.0; r := a / b; end;          { div by zero }
      1: begin a := 1e308; b := 10.0; r := a * b; end;       { overflow }
      2: begin a := 0.0; b := 0.0; r := a / b; end;          { 0/0 = invalid }
      3: begin a := 1e-300; b := 1e-30; r := a * b; end;     { underflow }
      4: begin a := 1.0; b := 3.0; r := a / b; end;          { inexact }
    end;
    WriteLn('no trap, r=', r);
  except
    WriteLn('trapped si_code=', lastCode);
  end;
  old := __pxxSetFPUMask(keep);
end;

begin
  SetSignalHandler(8, @OnFPE);

  { 1. The default is quiet IEEE, and stays it. }
  WriteLn('default mask=', __pxxGetFPUMask);
  a := 1.0; b := 0.0; r := a / b;
  WriteLn('quiet 1/0=', r);
  a := 1e308; b := 10.0; r := a * b;
  WriteLn('quiet overflow=', r);
  a := 0.0; b := 0.0; r := a / b;
  WriteLn('quiet 0/0=', r);

  { 2. Round trip: set returns the previous value, and restoring it restores. }
  old := __pxxSetFPUMask(ALL_MASKED and not M_ZERODIV);
  WriteLn('prev=', old, ' now=', __pxxGetFPUMask);
  old := __pxxSetFPUMask(old);
  WriteLn('after restore=', __pxxGetFPUMask, ' (returned ', old, ')');

  { 3. Each cause traps, and si_code says WHICH — the fact an FPC-style
       205/206/207/208 mapping is built out of. }
  Trap(M_ZERODIV,   0);
  Trap(M_OVERFLOW,  1);
  Trap(M_INVALID,   2);
  Trap(M_UNDERFLOW, 3);
  Trap(M_PRECISION, 4);

  { 4. Masked again: the same operations are quiet, and the mask is intact. }
  WriteLn('mask after=', __pxxGetFPUMask);
  a := 1.0; b := 0.0; r := a / b;
  WriteLn('quiet again=', r);
  WriteLn('FPE_FLTDIV=', FPE_FLTDIV, ' FLTOVF=', FPE_FLTOVF, ' FLTUND=',
          FPE_FLTUND, ' FLTRES=', FPE_FLTRES, ' FLTINV=', FPE_FLTINV);
end.
