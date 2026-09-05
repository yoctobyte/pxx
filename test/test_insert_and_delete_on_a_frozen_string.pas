program test_insert_and_delete_on_a_frozen_string;
{ `Insert` and `Delete` lower to __pxxStrInsert / __pxxStrDelete, both of which
  take `var s: AnsiString`. The intrinsic handed them the ADDRESS of the
  destination lvalue with no conversion — so for a ShortString or a `string[N]`
  the callee read an inline length prefix as a heap handle and dereferenced it.

    var T: ShortString;  T := 'abcdef';  Insert('XY', T, 1);   -> SEGFAULT

  Six lines, no out-of-range index anywhere, and the identical statement over a
  plain `string` in the same program is correct. The conformance row this comes
  from (tstring1) was skipped as "out-of-range/negative indices crashes", which
  named the wrong trigger: the indices are innocent.

  `Copy` and `SetLength` on the very same variable were always fine, and that is
  the discriminating observation — they take the string BY VALUE (IRLowerCallArg
  converts) or have their own lowering, so only the two `var`-parameter
  intrinsics ever saw the raw address. Both are asserted below as controls: if a
  future change breaks the frozen read-modify-write, these rows stay green and
  the Insert/Delete rows do not, which is what says the fix is in the right half.

  The guard on the Insert/Delete arms listed tyFixedString EXPLICITLY, so the
  frozen destination was admitted by the type test and then passed on
  unconverted — a guard that lets a value through to a crash.

  Byte-compared against FPC 3.2.2. Fails on pin v403 (214500da2) with a
  segmentation fault at the first Insert. }

var
  sh: shortstring;
  fx: string[20];
  ms: string;
begin
  sh := 'abcdef'; Insert('XY', sh, 1);   WriteLn('ins short ', sh);
  sh := 'abcdef'; Delete(sh, 2, 3);      WriteLn('del short ', sh);
  fx := 'abcdef'; Insert('XY', fx, 3);   WriteLn('ins fixed ', fx);
  fx := 'abcdef'; Delete(fx, 1, 2);      WriteLn('del fixed ', fx);
  ms := 'abcdef'; Insert('XY', ms, 1);   WriteLn('ins mgd   ', ms);
  ms := 'abcdef'; Delete(ms, 2, 3);      WriteLn('del mgd   ', ms);
  { the two that were never broken, kept as the discriminating controls }
  sh := 'abcdef'; WriteLn('copy short ', Copy(sh, 2, 3));
  sh := 'abcdef'; SetLength(sh, 3); WriteLn('setlen short ', sh);
  { the index clamps the helpers already implement, over a frozen destination }
  sh := 'abcdef'; Insert('Z', sh, 99);   WriteLn('ins past-end ', sh);
  sh := 'abcdef'; Delete(sh, 99, 2);     WriteLn('del past-end ', sh);
end.
