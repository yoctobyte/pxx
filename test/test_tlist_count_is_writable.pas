{ `L.Count := N` was refused with `property is read-only`. FPC declares
  `property Count: Integer read FCount write SetCount` on both TList and
  TFPList; pxx declared the getter and no setter, so the ordinary FPC idiom for
  unwinding a partially built list --

      for i := OldCount to L.Count - 1 do TFoo(L[i]).Release;
      L.Count := OldCount;

  -- did not compile. fcl-passrc pparser.pp:4768 is exactly that, in
  ParseVarList's error path.

  THE TWO HALVES OF SetCount ARE NOT SYMMETRIC AND THAT ASYMMETRY IS THE
  BEHAVIOUR, which is why there is a row for each rather than one resize row.
  SHRINKING NOTIFIES: FPC removes through Delete, so an owning descendant's
  Notify(lnDeleted) fires once per dropped element. GROWING DOES NOT: it exposes
  empty slots rather than adding elements, and those slots must read nil.

  THE `notify` ROW IS THE ONE THAT CANNOT BE CHECKED BY LOOKING AT THE LIST.
  A SetCount implemented as a bare SetLength gives the RIGHT Count and the RIGHT
  surviving elements — every other row here still passes — and silently leaks
  every dropped element in an owning list. That is the leak shape: the defect
  cannot fail a value assertion about the container, so the assertion has to be
  about the callback instead. TOwn counts lnDeleted rather than owning real
  objects on purpose: a count is comparable against fpc, where a leak is not.

  THE `nil` ROW EXISTS BECAUSE ITS RIGHT ANSWER MUST DIFFER FROM THE DEFAULT.
  A grown slot reading nil is only evidence if the slot could have read
  something else, so the list is filled with non-nil values first and the
  surviving element is asserted alongside — `kept = 1` is what separates
  "grew correctly" from "reallocated and lost everything".

  TFPList IS A SEPARATE ROW BECAUSE pxx'S HIERARCHY IS INVERTED FROM FPC'S:
  here TFPList descends from TList, in FPC TList wraps a TFPList, and FPC's
  TFPList.SetCount does NOT notify while its TList.SetCount does. Inheriting one
  implementation could therefore have diverged; measured, it does not — every
  row below is byte-identical to fpc 3.2.2 -Mobjfpc.
  feature-b-tlist-count-is-writable }
{$mode objfpc}
program test_tlist_count_is_writable;
uses classes;
type
  TOwn = class(TList)
  protected
    procedure Notify(Ptr: Pointer; Action: TListNotification); override;
  public
    Freed: Integer;
  end;

procedure TOwn.Notify(Ptr: Pointer; Action: TListNotification);
begin
  if Action = lnDeleted then Freed := Freed + 1;
end;

var
  L: TList;
  O: TOwn;
  F: TFPList;
  i: Integer;
begin
  L := TList.Create;
  for i := 1 to 5 do L.Add(Pointer(PtrInt(i)));
  L.Count := 3;
  WriteLn('shrink count = ', L.Count, ' last = ', PtrInt(L[2]));
  L.Count := 6;
  WriteLn('grow count   = ', L.Count, ' new slot nil = ', L[5] = nil, ' kept = ', PtrInt(L[0]));

  O := TOwn.Create;
  for i := 1 to 4 do O.Add(Pointer(PtrInt(i)));
  O.Count := 1;
  WriteLn('notify fired = ', O.Freed, ' count = ', O.Count);

  F := TFPList.Create;
  for i := 1 to 3 do F.Add(Pointer(PtrInt(i * 10)));
  F.Count := 2;
  WriteLn('tfplist      = ', F.Count, ' ', PtrInt(F[1]));
end.
