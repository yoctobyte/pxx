{ TWO specializations of one template, whose nested type is used as a generic
  argument. The hoisted name of one must not reach the other.

  `SetSpecSubs` and `CollectHoistCandidates` are two halves of ONE
  per-specialization state, and until 2026-09-09 only ParseSpecialization set
  both. The other three sites set the substitution and left the hoist table
  holding whichever specialization was collected LAST, so the method-impl
  header -- one token range shared by every specialization -- minted
  `TBox$Int64$TOwner$Byte$PT`: Int64's substitution with BYTE's hoisted PT.

  WHY BOTH ROWS MUST DIFFER IN THE POINTEE. Give the two owners the same
  argument and their two hoisted names coincide, and the test prints the right
  answer while reading the wrong row -- it would pass with the defect live.
  Int64 and Byte, so `PointeeSize` is 8 against 1 and a leaked row prints the
  OTHER row's number.

  AND NEITHER EXPECTED SIZE IS 4. `SizeOf` of an unrecorded type answers the
  int width here, so a size row expecting 4 cannot tell a correct answer from a
  blank one (CLAUDE.md, "choose a probe whose right answer differs from the
  default").

  The value rows are the second assertion and a different one: 70000 does not
  fit in a Byte, so a `Deref` reading through the wrong pointee truncates
  visibly rather than merely disagreeing about a width.

  bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template }
program test_a_hoisted_nested_type_does_not_leak_between_specializations;
{$MODE DELPHI}{$H+}
type
  TBox<T, P> = class
  public
    Q: P;
    function PointeeSize: Integer;
  end;

  TOwner<T> = class
  public type
    PT = ^T;
  public
    function MakeBox: TBox<T, PT>;
    function Deref(p: PT): T;
  end;

function TBox<T, P>.PointeeSize: Integer;
var q: P;
begin
  Result := SizeOf(q^);
end;

function TOwner<T>.MakeBox: TBox<T, PT>;
begin
  Result := TBox<T, PT>.Create;
end;

function TOwner<T>.Deref(p: PT): T;
begin
  Result := p^;
end;

var
  bi: TOwner<Int64>;
  by: TOwner<Byte>;
  vi: Int64;
  vb: Byte;
begin
  bi := TOwner<Int64>.Create;
  by := TOwner<Byte>.Create;
  vi := 70000;
  vb := 9;
  WriteLn('int64 ', bi.MakeBox.PointeeSize, ' ', bi.Deref(@vi));
  WriteLn('byte ', by.MakeBox.PointeeSize, ' ', by.Deref(@vb));
end.
