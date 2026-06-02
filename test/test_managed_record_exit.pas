{$define PXX_MANAGED_STRING}
program test_managed_record_exit;

{ Regression: returning a record VALUE via Exit(r) / Result must copy the whole
  record from the source's ADDRESS. The Exit lowering previously lowered the
  source record as a value (IR_LOAD_SYM, first 8 bytes), which COPY_REC then
  misread as a source pointer and segfaulted. Covers scalar and managed-string
  record payloads, via both Exit(r) and Result.

  Note: returning a Variant VALUE from a function (hidden-pointer result ABI for
  16-byte Variants) is still unimplemented and deliberately deferred — see the
  "results" item in docs/handover-sis-ai-2026-06-02.md. }

type
  TRec = record
    s1, s2: AnsiString;
    n: Integer;
  end;

  TScalarRec = record
    a, b: Integer;
  end;

function ReturnRecExit(const val: AnsiString): TRec;
var
  r: TRec;
begin
  r.s1 := val;
  r.s2 := 'world';
  r.n := 42;
  Exit(r);
end;

function ReturnRecResult(const val: AnsiString): TRec;
begin
  Result.s1 := val;
  Result.s2 := 'world';
  Result.n := 42;
end;

function ReturnScalarExit: TScalarRec;
var
  r: TScalarRec;
begin
  r.a := 7;
  r.b := 9;
  Exit(r);
end;

procedure Check(ok: Boolean);
begin
  if ok then writeln(1) else writeln(0);
end;

var
  r1, r2: TRec;
  s: TScalarRec;
begin
  { Managed-string record via Exit(r) }
  r1 := ReturnRecExit('hello');
  Check(r1.s1 = 'hello');
  Check(r1.s2 = 'world');
  Check(r1.n = 42);

  { Managed-string record via Result }
  r2 := ReturnRecResult('hello2');
  Check(r2.s1 = 'hello2');
  Check(r2.s2 = 'world');
  Check(r2.n = 42);

  { Scalar record (no managed fields) via Exit(r) }
  s := ReturnScalarExit;
  Check(s.a = 7);
  Check(s.b = 9);

  { Reassign through the managed Exit path once more to exercise release of the
    previous payload before the fresh copy. }
  r1 := ReturnRecExit('again');
  Check(r1.s1 = 'again');
  Check(r1.s2 = 'world');
  writeln('OK');
end.
