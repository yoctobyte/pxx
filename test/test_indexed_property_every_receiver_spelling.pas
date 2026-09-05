{ ONE indexed property, read and written through every receiver spelling there
  is. This is the matrix the direction decision needs, and it is here because
  that decision used to be seven copies of a bracket-balancing peek — four
  careful, three not — with nothing at any site saying which kind it was.

  The DIRECTION is what varies. `:=` follows the SUBSCRIPT, not the property
  name, so an arm that peeks at the next token sees `[`, concludes "read", and
  calls the GETTER for a write. Every row here is a write followed by a read of
  the same slot; the getter adds 100 and the setter stores plain, so a row that
  chose the wrong accessor prints a number 100 off rather than failing to
  compile.

  Four receiver spellings, and they were reaching different arms:
    bare `A[i]` inside a method          — SelfMemberCi, the unqualified arm
    `Self.A[i]`                          — the selector walker
    `c.A[i]`                             — the qualified member arm
    `with c do A[i]`                     — the with-scope arm
  A fifth, `TCls.A[i]`, is a CLASS property and lives in
  test_class_property_indexed.pas, which is where the `index N` modifier is
  covered too.

  Expected output is fpc 3.2.2's own.
  refactor-p-one-lvalue-path-for-statements-and-expressions }
program test_indexed_property_every_receiver_spelling;
{$mode delphi}

type
  TCls = class
  private
    FA: array[0..7] of LongInt;
    function GetA(i: LongInt): LongInt;
    procedure SetA(i, v: LongInt);
    function GetC(r, c: LongInt): LongInt;
    procedure SetC(r, c, v: LongInt);
  public
    property A[i: LongInt]: LongInt read GetA write SetA;
    { multi-index, so the peek has more than one token to cross }
    property Cells[r, c: LongInt]: LongInt read GetC write SetC;
    procedure BareSpelling;
    procedure SelfSpelling;
  end;

function TCls.GetA(i: LongInt): LongInt;
begin Result := FA[i] + 100; end;

procedure TCls.SetA(i, v: LongInt);
begin FA[i] := v; end;

function TCls.GetC(r, c: LongInt): LongInt;
begin Result := FA[r * 2 + c] + 100; end;

procedure TCls.SetC(r, c, v: LongInt);
begin FA[r * 2 + c] := v; end;

procedure TCls.BareSpelling;
begin
  A[0] := 1;
  WriteLn('bare  ', FA[0], ' ', A[0]);
  { the subscript is itself an indexed expression: an unbalanced peek stops
    inside it and never sees the `:=` }
  FA[7] := 1;
  A[FA[7]] := 2;
  WriteLn('bare  ', FA[1], ' ', A[1]);
end;

procedure TCls.SelfSpelling;
begin
  Self.A[2] := 3;
  WriteLn('self  ', FA[2], ' ', Self.A[2]);
  Self.Cells[1, 1] := 4;
  WriteLn('self  ', FA[3], ' ', Self.Cells[1, 1]);
end;

var
  c: TCls;
begin
  c := TCls.Create;
  c.BareSpelling;
  c.SelfSpelling;

  c.A[4] := 5;
  WriteLn('qual  ', c.FA[4], ' ', c.A[4]);
  c.Cells[2, 1] := 6;
  WriteLn('qual  ', c.FA[5], ' ', c.Cells[2, 1]);

  with c do
  begin
    A[6] := 7;
    WriteLn('with  ', FA[6], ' ', A[6]);
    Cells[3, 1] := 8;
    WriteLn('with  ', FA[7], ' ', Cells[3, 1]);
  end;
end.
