program test_a_var_record_parameter_writes_back_through_every_receiver_that_has_no_implementation_header;
{ A `var` record parameter must write back through the CALLER's storage, whatever
  kind of receiver the call goes through.

  WHY THE POPULATION IS EXACTLY THESE THREE, and it is a structural argument
  rather than a sample: a method is DECLARED TWICE -- once in the class or
  interface body, once at its implementation header -- and the header goes
  through ParseSubroutine, which overwrites the parameter row. So a row written
  wrong by the four parameter parsers in pasparser_decl.inc is REPAIRED for
  every routine that has an implementation header, and survives only where none
  exists: an INTERFACE method, a `virtual; abstract` method, and a procedural
  TYPE. The `class body impl`, `free routine` and `record method` rows are the
  controls that have one.

  ProcParamExplicitByRef -- "declared `var`/`out`/`const` at the SOURCE level,
  as opposed to promoted to by-ref because the >8-byte record ABI forces it" --
  was written only by ParseSubroutine. Reading False, ir.inc's by-ref arm takes
  the private-copy path meant for an ABI-promoted by-value parameter, so the
  callee writes a temp and the caller's record is never touched. No crash, no
  diagnostic, a plausible value. Measured 2026-09-06 against fpc 3.2.2:
  pxx 301/401/1/1/501/1 where fpc gives 301/401/101/201/501/401.

  SIZE IS IRRELEVANT TO THIS DEFECT, which is not what the flag's own name
  suggests and is worth one row saying so. ProcParamExplicitByRef exists to tell
  a source-level `var` from a by-value record the >8-byte ABI promoted, so a
  reader naturally expects a small record to be safe -- and it is not: a `var`
  parameter carries IsRef at ANY size, so ir.inc reaches the same arm and reads
  the same False. The 4-byte `iface small rec` row was written here as a control
  that could not fail and FAILED on the positive control (1 where 11 was
  wanted), which is how it became a row. TBig stays 24 bytes because the flag's
  purpose is the >8-byte case; TSm is here because the bug is not.

  The `const` and by-value rows below are the OTHER half -- writing
  ProcParamExplicitByRef without ProcParamIsConst turns a `const` record
  parameter into one that refuses a non-lvalue argument, because
  ByRefArgNeedsLvalue asks `ExplicitByRef and not IsConst`.

  bug-p-a-var-record-parameters-write-back-is-dropped-for-every-declaration-that-has-no-implementation-header }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}

type
  TBig = record a, b, c: Int64; end;   { 24 bytes -- ABI-promoted to by-ref }
  TSm  = record a: Integer; end;       { small -- never promoted }

  TCbVar   = procedure(var r: TBig);
  TCbConst = procedure(const r: TBig);
  TCbVal   = procedure(r: TBig);

  IFoo = interface
    ['{11111111-2222-3333-4444-555555555555}']
    procedure Bump(var r: TBig);
    procedure CBump(const r: TBig);
    procedure VBump(r: TBig);
    procedure SBump(var s: TSm);
  end;

  TBase = class(TInterfacedObject)
    procedure ABump(var r: TBig); virtual; abstract;
  end;

  TFoo = class(TBase, IFoo)
    procedure Bump(var r: TBig);
    procedure ABump(var r: TBig); override;
    procedure MBump(var r: TBig);
    procedure CBump(const r: TBig);
    procedure VBump(r: TBig);
    procedure SBump(var s: TSm);
  end;

  TRec = record
    procedure RBump(var r: TBig);
  end;

var Fail: Integer;

procedure Row(const nm: AnsiString; got, want: Int64);
begin
  WriteLn(nm, ' ', got);
  if got <> want then begin WriteLn('  MISMATCH: wanted ', want); Inc(Fail); end;
end;

procedure FreeBump(var r: TBig);    begin r.a := r.a + 400; end;
procedure FreeConst(const r: TBig); begin WriteLn('const reads      ', r.a); end;
procedure FreeVal(r: TBig);         begin r.a := 9999; end;

procedure TFoo.Bump(var r: TBig);   begin r.a := r.a + 100; end;
procedure TFoo.ABump(var r: TBig);  begin r.a := r.a + 200; end;
procedure TFoo.MBump(var r: TBig);  begin r.a := r.a + 300; end;
procedure TFoo.CBump(const r: TBig);begin WriteLn('iface const      ', r.a); end;
procedure TFoo.VBump(r: TBig);      begin r.a := 9999; end;
procedure TFoo.SBump(var s: TSm);   begin s.a := s.a + 10; end;
procedure TRec.RBump(var r: TBig);  begin r.a := r.a + 500; end;

function MakeBig: TBig; begin Result.a := 7; Result.b := 0; Result.c := 0; end;

var
  f: TFoo; i: IFoo; b: TBase; q: TRec;
  r: TBig; s: TSm;
  cbv: TCbVar; cbc: TCbConst; cbl: TCbVal;
begin
  Fail := 0;
  f := TFoo.Create;
  b := f; i := f;
  cbv := @FreeBump; cbc := @FreeConst; cbl := @FreeVal;

  { the three receivers whose declaration IS repaired by an implementation header }
  r.a := 1; f.MBump(r);   Row('class body impl ', r.a, 301);
  r.a := 1; FreeBump(r);  Row('free routine    ', r.a, 401);
  r.a := 1; q.RBump(r);   Row('record method   ', r.a, 501);

  { the three with no implementation header -- the whole point of this file }
  r.a := 1; i.Bump(r);    Row('interface method', r.a, 101);
  r.a := 1; b.ABump(r);   Row('abstract method ', r.a, 201);
  r.a := 1; cbv(r);       Row('proc-type call  ', r.a, 401);

  { NOT a control: a 4-byte record fails identically, because a `var` parameter
    is by-ref at any size and the arm keys on the column, not on the size the
    column was invented for. }
  s.a := 1; i.SBump(s);   Row('iface small rec ', s.a, 11);

  { the const/by-value half. A non-lvalue argument to a `const` record parameter
    must still be accepted, and a by-value parameter must NOT write back. }
  cbc(MakeBig());
  i.CBump(MakeBig());
  r.a := 5; i.VBump(r);   Row('iface by-value  ', r.a, 5);
  r.a := 5; cbl(r);       Row('proct by-value  ', r.a, 5);

  if Fail = 0 then WriteLn('VARRECWRITEBACK OK')
  else WriteLn('VARRECWRITEBACK FAILED ', Fail);
end.
