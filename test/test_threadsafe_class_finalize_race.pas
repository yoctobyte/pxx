program test_threadsafe_class_finalize_race;
{ The POSITIVE CONTROL for the {$ifndef PXX_TS_HARDLOCK} around
  PXXClassFinalize's managed-field pass (builtinheap.pas), which exists so that
  x86-64 --threadsafe does NOT release string/dynarray class fields from Pascal
  with the codegen heap lock unheld.

  That guard costs a real leak — bug-a-threadsafe-on-x86-64-leaks-every-managed
  -class-field-and-it-is-not-benign measures 392 kB -> 398336 kB on 200k
  instances — so the reflex on reading it is "just delete the ifdef". This
  program is what says no. Measured 2026-08-31, three runs each:

    guard ON,  NT=4   errors=0 RACE OK   (3/3)
    guard OFF, NT=4   SIGSEGV            (3/3)
    guard OFF, NT=1   errors=0 RACE OK   (3/3)

  The NT=1 row is what makes it a RACE rather than a plain double-free, and it
  is why this test needs threads to have any value at all: at NT=1 the
  unguarded code is correct.

  So this passes today for a reason that is itself a bug — the pass it guards
  never runs. It is here for the FIX: whichever way that lands (a Pascal-visible
  acquire on the codegen lock, or moving the wrap into codegen with the
  interface pass kept outside it), the fix must keep this green, and a fix that
  simply removes the guard will not.

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
