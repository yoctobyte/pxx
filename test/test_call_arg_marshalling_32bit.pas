{ The 32-bit call-argument marshalling MATRIX: every by-value argument shape
  that occupies more (or fewer) than one word, crossed with every call KIND.

  Why a matrix and not a case: each 32-bit backend writes the by-value argument
  ladder out once per call kind -- direct, indirect (proc-var), virtual -- and
  the copies drifted. IR_VIRTUAL_CALL had no ladder at all in any of the three
  backends for years (bug-a-virtual-method-int64-in-and-out-32bit: silent wrong
  values on arm32/riscv32, a segfault on i386, and it reached the RTL through
  TStream.GetPosition). The by-value set case was found by looking for the same
  omission on purpose. feature-a-unify-32bit-call-argument-marshalling is the
  structural fix; this is the net under it.

  Every case sandwiches the interesting argument between plain Integers. That
  is deliberate: a wrong word count does not usually corrupt the wide argument
  itself, it SHIFTS every following argument's stack slot, so a trailing
  Integer that comes back wrong is the sensitive detector. A case that passed
  only the wide value would miss exactly the failure this whole family has.

  The 5..8 byte by-value record through a virtual call is the shape the ticket
  calls out as untested and working only by coincidence -- every backend
  happens to pass such records by address on the virtual path, which is an
  accident rather than a decision. If a backend ever changes that, this fails
  instead of silently corrupting an argument list. }
program test_call_arg_marshalling_32bit;
type
  TE = (eA, eB, eC, eD);
  TES = set of TE;
  TRec58 = record a, b: Integer; end;          { 8 bytes: the pair-or-address case }
  TRec5  = record a: Integer; b: Byte; end;    { 5 bytes: padded, still <= 8 }

  TProcI64 = function (p: Integer; const x: Int64; q: Integer): Integer;
  TProcDbl = function (p: Integer; d: Double; q: Integer): Integer;
  TProcSet = function (p: Integer; const s: TES; q: Integer): Integer;
  TProcRec = function (p: Integer; const r: TRec58; q: Integer): Integer;

  TB = class
  public
    function VI64(p: Integer; const x: Int64; q: Integer): Integer; virtual;
    function VDbl(p: Integer; d: Double; q: Integer): Integer; virtual;
    function VSgl(p: Integer; f: Single; q: Integer): Integer; virtual;
    function VSet(p: Integer; const s: TES; q: Integer): Integer; virtual;
    function VRec58(p: Integer; const r: TRec58; q: Integer): Integer; virtual;
    function VRec5(p: Integer; const r: TRec5; q: Integer): Integer; virtual;
    function VMixed(a: Integer; const x: Int64; b: Integer; d: Double; c: Integer): Integer; virtual;
  end;

{ Each body returns a value that depends on the WIDE argument and on BOTH
  sandwiching Integers, so a shifted slot cannot cancel out. }
function TB.VI64(p: Integer; const x: Int64; q: Integer): Integer;
begin VI64 := p * 100 + Integer(x mod 1000) * 10 + q; end;
function TB.VDbl(p: Integer; d: Double; q: Integer): Integer;
begin VDbl := p * 100 + Trunc(d) * 10 + q; end;
function TB.VSgl(p: Integer; f: Single; q: Integer): Integer;
begin VSgl := p * 100 + Trunc(f) * 10 + q; end;
function TB.VSet(p: Integer; const s: TES; q: Integer): Integer;
var e: TE; n: Integer;
begin n := 0; for e := eA to eD do if e in s then Inc(n); VSet := p * 100 + n * 10 + q; end;
function TB.VRec58(p: Integer; const r: TRec58; q: Integer): Integer;
begin VRec58 := p * 100 + (r.a + r.b) * 10 + q; end;
function TB.VRec5(p: Integer; const r: TRec5; q: Integer): Integer;
begin VRec5 := p * 100 + (r.a + Integer(r.b)) * 10 + q; end;
function TB.VMixed(a: Integer; const x: Int64; b: Integer; d: Double; c: Integer): Integer;
begin VMixed := a * 10000 + Integer(x mod 100) * 1000 + b * 100 + Trunc(d) * 10 + c; end;

{ Free functions with the SAME signatures: the direct-call and proc-var paths. }
function FI64(p: Integer; const x: Int64; q: Integer): Integer;
begin FI64 := p * 100 + Integer(x mod 1000) * 10 + q; end;
function FDbl(p: Integer; d: Double; q: Integer): Integer;
begin FDbl := p * 100 + Trunc(d) * 10 + q; end;
function FSet(p: Integer; const s: TES; q: Integer): Integer;
var e: TE; n: Integer;
begin n := 0; for e := eA to eD do if e in s then Inc(n); FSet := p * 100 + n * 10 + q; end;
function FRec58(p: Integer; const r: TRec58; q: Integer): Integer;
begin FRec58 := p * 100 + (r.a + r.b) * 10 + q; end;

var
  bad: Integer;
  o: TB;
  x: Int64;
  d: Double;
  f: Single;
  s: TES;
  r8: TRec58;
  r5: TRec5;
  pI: TProcI64;
  pD: TProcDbl;
  pS: TProcSet;
  pR: TProcRec;

{ Expected values are FPC's, from `fpc -Mobjfpc -O2` on this same source. Both
  printed AND checked: the printed form is what a cross-target A/B diff reads,
  the PASS line is what `make test` greps. }
procedure Chk(const lbl: string; got, want: Integer);
begin
  writeln(lbl, ' ', got);
  if got <> want then
  begin
    writeln('  MISMATCH: expected ', want);
    Inc(bad);
  end;
end;

begin
  bad := 0;
  o := TB.Create;
  x := 4294967296 + 7;     { 2^32+7: the high half is NOT zero, so dropping it shows }
  d := 6.0;
  f := 6.0;
  s := [eA, eC, eD];       { 3 members }
  r8.a := 2; r8.b := 4;
  r5.a := 2; r5.b := 4;

  { --- virtual: the path that had no ladder at all --- }
  Chk('v.i64  ', o.VI64(1, x, 9), 3139);
  Chk('v.dbl  ', o.VDbl(1, d, 9), 169);      { i386 had no double case: 840500009 }
  Chk('v.sgl  ', o.VSgl(1, f, 9), 169);      { i386+arm32 had no single case: 109 }
  Chk('v.set  ', o.VSet(1, s, 9), 139);
  Chk('v.rec8 ', o.VRec58(1, r8, 9), 169);
  Chk('v.rec5 ', o.VRec5(1, r5, 9), 169);
  Chk('v.mixed', o.VMixed(1, 42, 2, d, 3), 52263);

  { --- direct --- }
  Chk('d.i64  ', FI64(1, x, 9), 3139);
  Chk('d.dbl  ', FDbl(1, d, 9), 169);
  Chk('d.set  ', FSet(1, s, 9), 139);
  Chk('d.rec8 ', FRec58(1, r8, 9), 169);

  { --- indirect, through a proc-var: riscv32 had NO ladder here at all --- }
  pI := @FI64;   Chk('i.i64  ', pI(1, x, 9), 3139);
  pD := @FDbl;   Chk('i.dbl  ', pD(1, d, 9), 169);
  pS := @FSet;   Chk('i.set  ', pS(1, s, 9), 139);   { i386 had no set case here }
  pR := @FRec58; Chk('i.rec8 ', pR(1, r8, 9), 169);

  { --- a literal (not a variable) in the wide slot: a different IR shape --- }
  Chk('v.i64L ', o.VI64(1, 4294967303, 9), 3139);
  Chk('d.i64L ', FI64(1, 4294967303, 9), 3139);
  Chk('v.dblL ', o.VDbl(1, 6.0, 9), 169);

  o.Free;
  if bad = 0 then writeln('PASS') else writeln('FAIL ', bad);
end.
