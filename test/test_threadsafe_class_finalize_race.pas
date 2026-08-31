program test_threadsafe_class_finalize_race;
{ The POSITIVE CONTROL for the heap lock around PXXClassFinalizeManaged's
  field walk (emitted at the call site in ir_codegen.inc, because on x86-64
  --threadsafe the lock is the codegen BSS spinlock and Pascal cannot take it).

  Written 2026-08-31 to defend the guard it was about to replace, and it earned
  itself twice. Five configurations, three runs each, in the order they were
  measured:

    {$ifndef PXX_TS_HARDLOCK} guard ON,  NT=4   errors=0 RACE OK   (3/3)
    guard deleted,                       NT=4   SIGSEGV            (3/3)
    guard deleted,                       NT=1   errors=0 RACE OK   (3/3)
    the fix (walk under the emitted lock), NT=4  errors=0 RACE OK  (3/3)
    the fix with the acquire removed,      NT=4  SIGSEGV           (3/3)

  Rows 2 and 3 killed the one-line "just delete the ifdef" fix and showed the
  hazard is a genuine allocator RACE, not a double free — at NT=1 the unguarded
  code is correct. Row 5 is the one that matters now: it is this program run
  against the SHIPPED fix with only the lock taken back out, so it proves the
  test can still fail for the reason it claims to test. Without row 5 a green
  here would mean nothing, since the code path it guards changed underneath it.

  What the guard cost, and why deleting it was tempting: 392 kB -> 398336 kB on
  200k one-string holders (bug-a-threadsafe-on-x86-64-leaks-every-managed-class
  -field-and-it-is-not-benign). The leak and the safety are separate claims and
  were measured separately — with the acquire removed the leak is still fixed,
  which is exactly why a leak probe alone could never have caught row 5.

  Its sibling test_threadsafe_class_finalize_kinds covers the other four managed
  kinds, whose failure mode is a hang rather than a crash.

  Libc-free, --threadsafe. }
uses palthread, palthreadobj;

const
  NT = 4;
  K  = 20000;
  L  = 40;

type
  THolder = class
    S: AnsiString;
    constructor Create(c: Char);
  end;

constructor THolder.Create(c: Char);
var i: Integer;
begin
  S := '';
  for i := 1 to L do S := S + c;
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
    if Length(h.S) <> L then bad := True
    else
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
  if errors = 0 then writeln('RACE OK') else writeln('RACE FAIL');
end.
