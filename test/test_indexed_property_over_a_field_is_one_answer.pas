{ An indexed property whose accessors are FIELDS — a pxx extension, asserted
  for INTERNAL CONSISTENCY and against no oracle at all.

  THERE IS DELIBERATELY NO FPC ROW HERE, and that is the point of the file.
  fpc 3.2.2 refuses the declaration outright:

    Error: Incompatible types: got "TCls.Array[0..3] Of LongInt"
           expected "LongInt"

  so `property A[i: LongInt]: LongInt read FR write FW` over array fields is
  something we accept and fpc does not, which this repo says is NOT a defect.
  What IS a defect is answering differently in four places, and that is what
  this was doing. Measured 2026-09-05, one declaration, four receiver
  spellings, THREE answers:

    c.A[2] := 7          stored through FW  — correct
    Self.A[1] := 8       stored through FW  — correct
    A[1] := 8   (bare)   refused: `indexed property has no setter: A`
    with c do A[3] := 9  stored through FR  — SILENTLY, and the read-back
                                              agreed, because the read went to
                                              the same wrong place

  The with-scope row is the one worth having a test for. Both other failures
  announce themselves; that one certifies itself, because an `expect_same`
  comparing a write to its own read-back passes on a store that went to the
  wrong field.

  SO THE ASSERTION IS THAT THE FOUR SPELLINGS AGREE, not that any particular
  field is written. Read and write are deliberately DIFFERENT fields, which is
  the only way a wrong choice is observable: with `read FA write FA` every row
  here would pass on every compiler that parsed it at all.
  refactor-p-one-lvalue-path-for-statements-and-expressions }
program test_indexed_property_over_a_field_is_one_answer;
{$mode delphi}

type
  TCls = class
  public
    FR: array[0..7] of LongInt;
    FW: array[0..7] of LongInt;
    property A[i: LongInt]: LongInt read FR write FW;
    procedure BareSpelling;
    procedure SelfSpelling;
  end;

procedure TCls.BareSpelling;
begin
  A[0] := 1;
  WriteLn('bare  FR=', FR[0], ' FW=', FW[0]);
end;

procedure TCls.SelfSpelling;
begin
  Self.A[1] := 2;
  WriteLn('self  FR=', FR[1], ' FW=', FW[1]);
end;

var
  c: TCls;
begin
  c := TCls.Create;
  c.BareSpelling;
  c.SelfSpelling;

  c.A[2] := 3;
  WriteLn('qual  FR=', c.FR[2], ' FW=', c.FW[2]);

  with c do
  begin
    A[3] := 4;
    WriteLn('with  FR=', FR[3], ' FW=', FW[3]);
  end;

  { and the READ comes from the read field, in every spelling }
  c.FR[4] := 41; c.FW[4] := 42;
  WriteLn('read  ', c.A[4]);
  with c do WriteLn('read  ', A[4]);
end.
