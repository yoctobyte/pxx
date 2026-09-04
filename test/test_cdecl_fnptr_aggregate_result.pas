{ AN AGGREGATE RETURNED THROUGH A `cdecl` FUNCTION POINTER.

  IR_CALL_IND branches on ProcCdecl, and the CDECL arm on aarch64 and arm32
  never read IRCallDest -- so the hidden aggregate-result register (x8 / r12)
  held whatever was already in it and the callee's EmitAggregateDestStash
  prologue stored through garbage. SIGSEGV on any struct returned through a
  cdecl function pointer, at ONE byte, not at some size boundary.

  THIS FILE EXISTS BECAUSE THE PASCAL SPELLING IS WHAT PROVED THE DIAGNOSIS.
  The bug was found from C, and the obvious control -- the same program in
  Pascal, which worked -- said "the backend is fine, the C frontend is broken".
  That control was drawn from the WRONG POPULATION: an ordinary Pascal
  fn-pointer type is not cdecl. Add the keyword and nothing else and it
  segfaults identically on both targets. The discriminator is the CONVENTION,
  not the language; C merely reaches it on every function pointer, because
  CParseFnSigGroup marks every C fnptr signature ProcCdecl.

  So the C-side regression test cannot stand alone: it covers the arm through
  one language, and this covers the route that has no C in it at all.

  ROW 2 IS THE CONTROL AND NOT PADDING -- the same call through a NON-cdecl
  fn-pointer type, which always worked. It takes the internal arm, and a fix
  that repaired the cdecl arm by disturbing that one would pass row 1 while
  breaking everything else that calls through a proc variable.

  Sizes 4 / 12 / 32 bytes span the register-returned and memory-returned
  classes on every target. Values are width-independent so one expected
  transcript serves all of them.

  bug-a-the-cdecl-indirect-call-arm-never-sets-up-the-hidden-aggregate-result-register-on-aarch64-and-arm32 }
program test_cdecl_fnptr_aggregate_result;

type
  TSmall = record a: Integer; end;
  TP3    = record x, y, z: Integer; end;
  TBig   = record v: array[0..7] of Integer; end;

  TMkSmallC = function(s: Integer): TSmall; cdecl;
  TMkP3C    = function(s: Integer): TP3; cdecl;
  TMkBigC   = function(s: Integer): TBig; cdecl;
  TMkP3Pas  = function(s: Integer): TP3;            { the control: internal arm }

function MkSmallC(s: Integer): TSmall; cdecl;
begin
  MkSmallC.a := 42 + s;
end;

function MkP3C(s: Integer): TP3; cdecl;
begin
  MkP3C.x := 7 + s; MkP3C.y := 11; MkP3C.z := 13;
end;

function MkBigC(s: Integer): TBig; cdecl;
var i: Integer;
begin
  for i := 0 to 7 do MkBigC.v[i] := i * 10 + s;
end;

function MkP3Pas(s: Integer): TP3;
begin
  MkP3Pas.x := 7 + s; MkP3Pas.y := 11; MkP3Pas.z := 13;
end;

var
  fSmall: TMkSmallC;
  fP3:    TMkP3C;
  fBig:   TMkBigC;
  fPas:   TMkP3Pas;
  rs: TSmall;
  r3: TP3;
  rb: TBig;
begin
  fP3 := @MkP3C;
  r3 := fP3(0);
  WriteLn('1 ', r3.x, ' ', r3.y, ' ', r3.z);

  fPas := @MkP3Pas;                 { control: the non-cdecl route }
  r3 := fPas(0);
  WriteLn('2 ', r3.x, ' ', r3.y, ' ', r3.z);

  r3 := MkP3C(0);                   { control: a DIRECT cdecl call }
  WriteLn('3 ', r3.x, ' ', r3.y, ' ', r3.z);

  fSmall := @MkSmallC;              { 4 bytes -- the size that also segfaulted }
  rs := fSmall(0);
  WriteLn('4 ', rs.a);

  fBig := @MkBigC;                  { 32 bytes -- returned in memory everywhere }
  rb := fBig(0);
  WriteLn('5 ', rb.v[0], ' ', rb.v[3], ' ', rb.v[6], ' ', rb.v[7]);

  r3 := fP3(1);                     { the argument must still arrive }
  WriteLn('6 ', r3.x, ' ', r3.y, ' ', r3.z);
end.
