program test_rtti_emit;
{ Phase 1 RTTI emission regression. Verifies (via --dump-rtti, checked in the
  Makefile) that published props/methods across a parent/child hierarchy emit
  with correct names, kinds, field offsets and resolved proc indices. The
  runtime body exercises field-backed published props to prove the program
  still compiles and runs end to end. Method addresses in the blob are
  validated at runtime in Phase 2. }
type
  TAlign = (alNone, alLeft, alRight, alClient);
  TBase = class
  private
    FId: Integer;
  published
    property Id: Integer read FId write FId;
    procedure Notify;
  end;

  TChild = class(TBase)
  private
    FCaption: string;
    FOwner: TBase;
    FAlign: TAlign;
  published
    property Caption: string read FCaption write FCaption;
    property Owner: TBase read FOwner write FOwner;
    property Align: TAlign read FAlign write FAlign;
  end;

procedure TBase.Notify;
begin
  writeln('notify');
end;

var
  c: TChild;
begin
  c := TChild.Create;
  { field-backed published property round-trip (read + write via FId) }
  c.Id := 42;
  writeln(c.Id);
  { enum-typed published property round-trip }
  c.Align := alClient;
  writeln(Ord(c.Align));
end.
