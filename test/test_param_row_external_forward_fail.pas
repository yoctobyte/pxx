{ %FAIL-style negative: a routine's declared parameter shape must survive to
  the CALLER, on every registration path — not just the one with a body.

  `procedure g(p: PInteger)` with a BODY correctly refuses an object argument.
  The identical line declared `external 'libc.so.6' name 'abs'` compiled clean and
  handed libc an object pointer, and the same declaration written `forward`
  accepted one at any call parsed before the body. FPC rejects all three.

  Cause: ParseSubroutine registers params on THREE paths — `external` (which
  then Exits), forward/interface, and the body pass — and each hand-copied its
  own subset of the ~20 durable ProcParam* columns. Measured 2026-08-30: body
  wrote all of them, forward wrote 14, `external` wrote THREE. `ProcParamPtrElemTk`
  stayed at the tyUnknown sentinel, and the narrowing guard reads that sentinel
  as "untyped pointer, permit anything" — so it failed OPEN. It did not fire and
  pass; it never ran with a real value.

  Row 3 is the arm that already worked and must stay in the file: it is what
  proves widening the other two did not break the path that was fine.

  The sibling test_param_row_external_forward_ok.pas is the other half, and it
  is the one that matters more here — the SAME omission that failed open on a
  pointer failed CLOSED on a default argument, so a fix measured only by what it
  starts refusing would have missed half its own effect.
  bug-a-an-external-routines-pointer-param-pointee-is-never-recorded-so-a-class-argument-is-accepted }
program test_param_row_external_forward_fail;
{$mode objfpc}{$H+}
type
  PInteger = ^Integer;
  TFoo = class end;
var f: TFoo;
procedure ext(p: PInteger); external 'libc.so.6' name 'abs';
procedure fwd(p: PInteger); forward;
procedure bodied(p: PInteger); begin end;
{ the call site that matters for `fwd`: parsed BEFORE fwd's body exists }
procedure caller;
begin
  ext(f);       { 1 external      }
  fwd(f);       { 2 forward, called before its body }
  bodied(f);    { 3 body — the arm that already worked }
end;
procedure fwd(p: PInteger); begin end;
begin
  f := TFoo.Create;
  caller;
end.
