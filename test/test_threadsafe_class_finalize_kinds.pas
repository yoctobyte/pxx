program test_threadsafe_class_finalize_kinds;
{ The other four managed field kinds, under the same concurrent churn that
  test_threadsafe_class_finalize_race applies to the string kind.

  That test is the positive control for the LOCK; this one is the positive
  control for the lock's SCOPE. The x86-64 --threadsafe fix runs
  PXXClassFinalizeManaged with the codegen heap lock held, and the whole subtree
  it reaches must therefore take no lock of its own — PXXStrDecRef,
  PXXDynArrayRelease, PXXRecordRelease and PXXVarClear. Any one of them holding
  an AnsiString LOCAL would be enough to break it: the scope-exit epilogue of
  that local calls the AnsiStrRelease blob, which acquires the same
  non-reentrant spinlock, and the program HANGS rather than crashing.

  A hang is why this is worth its own program. The string test cannot find it,
  because kind 1 is the one arm of PXXRecordRelease that is a single call with
  no locals; the dynarray, record and variant arms are the ones with room for
  the mistake, and none of them was reachable from any concurrent test before.

  So the assertion is not only errors=0 — it is that this TERMINATES.
  bug-a-threadsafe-on-x86-64-leaks-every-managed-class-field-and-it-is-not-benign }
uses palthread, palthreadobj;

const
  NT = 4;
  K  = 8000;
  L  = 24;
  AN = 8;

type
  TInner = record
    RS: AnsiString;
  end;

  THolder = class
    S: AnsiString;     { kind 1 }
    A: array of Integer; { kind 2 }
    R: TInner;         { kind 3, itself holding a kind 1 }
    V: Variant;        { kind 5 }
    constructor Create(c: Char);
  end;

constructor THolder.Create(c: Char);
var i: Integer;
begin
  S := '';
  for i := 1 to L do S := S + c;
  SetLength(A, AN);
  for i := 0 to AN - 1 do A[i] := Ord(c) + i;
  R.RS := S + '-r';
  V := S;
end;

var
  errors: Integer;     { atomic: instances that read back a foreign field }

type
  TChurn = class(TThread)
  public
    Tag: Char;
  protected
    procedure Execute; override;
  end;

procedure TChurn.Execute;
var
  j, b: Integer;
  h: THolder;
  bad: Boolean;
  ignore: Int64;
begin
  for j := 1 to K do
  begin
    h := THolder.Create(Tag);
    bad := False;
    if Length(h.S) <> L then bad := True;
    if Length(h.A) <> AN then bad := True
    else
      for b := 0 to AN - 1 do
        if h.A[b] <> Ord(Tag) + b then bad := True;
    if Length(h.R.RS) <> L + 2 then bad := True;
    if h.R.RS[L + 2] <> 'r' then bad := True;
    if not bad then
      for b := 1 to L do
        if h.S[b] <> Tag then bad := True;
    if bad then ignore := __pxxatomic_add(@errors, 1);
    h.Free;
  end;
end;

var
  w: array[0..NT-1] of TChurn;
  i: Integer;
begin
  errors := 0;
  for i := 0 to NT - 1 do
  begin
    w[i] := TChurn.Create(True);
    w[i].Tag := Chr(Ord('A') + i);
  end;
  for i := 0 to NT - 1 do w[i].Start;
  for i := 0 to NT - 1 do w[i].WaitFor;

  writeln('errors=', errors);
  if errors = 0 then writeln('KINDS OK') else writeln('KINDS FAIL');
end.
