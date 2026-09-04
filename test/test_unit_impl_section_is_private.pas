program test_unit_impl_section_is_private;
{ The POSITIVE half of bug-p-a-units-implementation-section-is-visible-to-its-importers:
  what must still work, and what the leak silently changed.

  Row 1 is the control from the right population -- an interface name, which
  must stay reachable; a fix that hid it would pass a "the private names are
  gone" test and be useless.

  Row 2 is the one that actually catches a regression by VALUE. The unit's
  implementation declares `PWord = ^NativeInt`; the builtin is `^UInt16`. Under
  the leak the private alias WON here (FindTypeAlias runs before the builtin
  chain and cannot tell a leaked row from the program's own), so SizeOf(p^) was
  8 and a write through it clobbered six extra bytes. Both expected values are
  chosen to differ from the failure value: 2 vs 8, and $FFFF vs a full word. }
uses unit_impl_private;

var
  n: NativeInt;
  p: PWord;
  fail: Integer;

begin
  fail := 0;

  if ImplPrivateExported <> 4249 then
  begin
    WriteLn('interface routine: got ', ImplPrivateExported, ' want 4249');
    fail := fail + 1;
  end;

  { PWord must mean the BUILTIN ^UInt16 here, not the unit's private ^NativeInt. }
  if SizeOf(p^) <> 2 then
  begin
    WriteLn('SizeOf(PWord^): got ', SizeOf(p^), ' want 2 (leaked ^NativeInt would give ', SizeOf(NativeInt), ')');
    fail := fail + 1;
  end;

  n := -1;
  p := PWord(@n);
  p^ := 0;
  { Two bytes cleared, not eight: the remaining bytes of `n` must survive. }
  if n = 0 then
  begin
    WriteLn('write through PWord cleared the whole word -- the private ^NativeInt is back');
    fail := fail + 1;
  end;
  if n <> NativeInt(-1) - $FFFF then
  begin
    WriteLn('write through PWord: got ', n, ' want ', NativeInt(-1) - $FFFF);
    fail := fail + 1;
  end;

  WriteLn('fail=', fail);
  if fail = 0 then WriteLn('IMPLPRIVATE OK') else WriteLn('IMPLPRIVATE BAD');
end.
