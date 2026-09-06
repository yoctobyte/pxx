program test_delphi_mode_binds_a_bare_routine_name;
{ THE OTHER SIDE OF THE FLAG, and it must not move. `$mode delphi` binds a bare
  routine name to its ADDRESS -- defs.inc calls this "the one behavioural delta"
  of that mode -- so the spellings the refusal beside this file rejects are
  CORRECT here and still compile.

  Fixing the default-mode crash by adopting Delphi's binding everywhere would
  also have removed it, and was rejected deliberately: that deletes the delta,
  which is a dialect decision and not something to arrive at while fixing a
  segfault.
  bug-p-a-bare-function-name-assigned-to-a-procedural-variable-segfaults-outside-delphi-mode

  ROWS C..H WERE ADDED 2026-09-06 AND THE PREVIOUS VERSION OF THIS FILE SAID WHY
  THEY WERE ABSENT: the Delphi arm was keyed on the destination SYMBOL, so
  `r.f := G` asked about `r` and `a[0] := G` asked about `a`, neither of which is
  proc-typed. Those two SIGSEGV'd on pin v404, were REFUSED after the
  default-mode fix, and are now bound. The arm asks PasNodeProcSig about the
  destination NODE instead; on a plain identifier that is exactly SymProcSig, so
  rows A and B are unchanged by construction.
  bug-p-delphi-mode-binds-a-bare-routine-name-only-for-a-variable-target

  ROWS E AND F ARE THE ROWS THAT SEPARATE THIS RULE FROM THE NEXT-WIDER ONE.
  `f := MakeCb` is a bare routine name too, and Delphi does NOT take its address:
  MakeCb is a paramless function whose result FITS a procedural target, so it is
  CALLED. A rule spelled "a bare routine name in Delphi mode is its address"
  passes every other row here and fails exactly these two -- and getting it wrong
  is not a diagnostic, it stores a code address where a value belongs.
  Row F is the field spelling of the same test, because the kind now comes off
  the destination NODE and a field is where a symbol-keyed reading would answer
  about the record.

  ROWS G AND H ARE THE METHOD-POINTER FACE. `procedure of object` is a 16-byte
  a `Code,Data` pair record rather than a plain pointer, so it takes the other branch of
  the same rule; a fix that only reached the tyPointer branch passes A..F. }
{$mode delphi}

type
  TF   = function: Integer;
  TSel = procedure of object;
  TRec = record f: TF; s: TSel; end;
  TC   = class procedure M; end;

function G: Integer;
begin
  G := 7;
end;

function MakeCb: TF;
begin
  MakeCb := @G;
end;

procedure TC.M;
begin
  WriteLn('M ran');
end;

procedure Use(h: TF);
begin
  WriteLn('B ', h());
end;

var
  f: TF; r: TRec; a: array[0..1] of TF;
  o: TC; s: TSel; sa: array[0..0] of TSel;

begin
  f := G;   WriteLn('A ', f());
  Use(G);
  Use(@G);

  { the two spellings the symbol-keyed arm never reached }
  r.f := G;    WriteLn('C ', r.f());
  a[0] := G;   WriteLn('D ', a[0]());

  { …and the ones it must still CALL rather than bind }
  f := MakeCb;    WriteLn('E ', f());
  r.f := MakeCb;  WriteLn('F ', r.f());

  { the method-pointer branch, through a field and an element }
  o := TC.Create;
  s := o.M;       Write('G '); s();
  r.s := o.M;     Write('H '); r.s();
  sa[0] := o.M;   Write('I '); sa[0]();
end.
