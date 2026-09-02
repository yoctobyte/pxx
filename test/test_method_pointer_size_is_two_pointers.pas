program test_method_pointer_size_is_two_pointers;
{ A `procedure of object` is a two-pointer {Code, Data} record, so its size is
  2 * the TARGET's pointer size. `EnsureMethodPtrRec` minted it with literal
  64-bit constants -- `UClsSize_ := 16; UClsAlign := 8;` -- so SizeOf answered
  16 on every 32-bit target while the equivalent user-declared
  `record Code, Data: Pointer` answered 8 on the same target. Measured by
  running on i386, arm32 and riscv32.

  Nothing was corrupted: the STORE was always target-aware (a method pointer
  read back through such a record returns the object in Data at offset 4 on
  i386), and the over-sized temp stayed inside its own allocation. The cost was
  eight wasted bytes per value and a SizeOf a program can read back wrong.

  THE ASSERTIONS ARE RELATIONAL, not per-target constants: the method pointer
  must equal the hand-written two-pointer record, and both must equal
  2 * SizeOf(Pointer). So the file carries no expected widths and passes on
  every target while printing a different correct number on each -- 16 on
  x86-64, 8 on the 32-bit ones.

  AND IT CALLS. A size row alone cannot see the failure mode a size change
  would introduce: shrinking the record is only correct if the call path never
  relied on the old width, so the test assigns a method pointer, calls through
  it, and checks the receiver saw its own object -- which is what would break
  if Data were read at the wrong offset.
  bug-a-method-pointer-record-is-hard-sized-16-bytes-on-32-bit-targets }

type
  TNotify = procedure(x: Integer) of object;
  TTwoPtr = record Code, Data: Pointer; end;

  TSink = class
    Tag: Integer;
    Seen: Integer;
    procedure Take(x: Integer);
  end;

procedure TSink.Take(x: Integer);
begin
  Seen := Tag * 1000 + x;
end;

var
  a, b: TSink;
  m: TNotify;
  fails: Integer;
begin
  fails := 0;

  { the declared size must match the hand-written equivalent, and both must be
    two target pointers }
  if SizeOf(TNotify) <> SizeOf(TTwoPtr) then
  begin
    WriteLn('FAIL methptr ', SizeOf(TNotify), ' vs record ', SizeOf(TTwoPtr));
    fails := fails + 1;
  end;
  if SizeOf(TNotify) <> 2 * SizeOf(Pointer) then
  begin
    WriteLn('FAIL methptr ', SizeOf(TNotify), ' vs 2*ptr ', 2 * SizeOf(Pointer));
    fails := fails + 1;
  end;

  { ...and it still dispatches to the right object. Two receivers, so a Data
    read at the wrong offset cannot pass by landing on the only object there. }
  a := TSink.Create; a.Tag := 1;
  b := TSink.Create; b.Tag := 2;

  m := @a.Take;  m(7);
  if a.Seen <> 1007 then begin WriteLn('FAIL a.Seen=', a.Seen); fails := fails + 1; end;

  m := @b.Take;  m(9);
  if b.Seen <> 2009 then begin WriteLn('FAIL b.Seen=', b.Seen); fails := fails + 1; end;
  if a.Seen <> 1007 then begin WriteLn('FAIL a clobbered: ', a.Seen); fails := fails + 1; end;

  if fails = 0 then
    WriteLn('METHPTR OK ', SizeOf(TNotify), ' ', SizeOf(Pointer));

  { EXIT NONZERO ON FAILURE. testmgr treats a nonzero run as a failure, and
    printing FAIL while returning 0 is a test that cannot fail in the dimension
    the harness actually reads -- verified by running this file against the
    PINNED compiler for i386, where it printed two FAIL lines and still exited
    0 before this line existed.

    Deliberately no `.expected` file: the correct output DIFFERS per target
    (16/8 on x86-64, 8/4 on the 32-bit ones), so a stored transcript would
    either pin the host's answer and fail every cross run, or have to be
    per-target. The assertions are relational for the same reason. }
  Halt(fails);
end.
