program test_string_rtl_in_frozen_mode;
{ The System string routines under -uPXX_MANAGED_STRING (frozen strings), the
  mode docs/targets/esp32.md recommends for small ESP images. Built by the
  Makefile BOTH ways against one .expected, which is fpc 3.2.2's output.
  Before 2026-09-28, frozen mode printed 0 and [] for `s := Copy('abcdef', 1,
  3)`, and garbage for UpCase and Space. The builtin is compiled frozen there,
  so its helpers return frozen strings, and the intrinsic arms tagged the call
  AnsiString. Delete and Insert on a frozen variable changed nothing: they went
  through a managed temp that the frozen helper never wrote. }
var s: string[16]; u: string; a: AnsiString; ss: ShortString;
begin
  s := Copy('abcdef', 1, 3); WriteLn(Length(s), ' [', s, ']');
  u := 'abcdef'; s := Copy(u, 2, 3); WriteLn(Length(s), ' [', s, ']');
  u := Copy(u, 2, 2); WriteLn(Length(u), ' [', u, ']');
  WriteLn('[', Copy('xyz', 2, 1), ']');
  a := Copy('abcdef', 4, 9); WriteLn(Length(a), ' [', a, ']');
  a := 'hey'; s := Copy(a, 1, 2); WriteLn(Length(s), ' [', s, ']');
  u := 'hello';
  WriteLn(Pos('l', u), ' ', Pos('l', 'hello'), ' ', Pos('l', u, 4), ' ', Pos('z', u));
  s := Space(3); WriteLn(Length(s), ' [', s, ']');
  s := UpCase(u); WriteLn(Length(s), ' [', s, ']');
  WriteLn('[', UpCase('ab'), '] ', UpCase('q'));
  Delete(u, 1, 2); WriteLn('[', u, ']');
  Insert('ZZ', u, 2); WriteLn('[', u, ']');
  s := 'abcdef'; Delete(s, 3, 2); Insert('-', s, 1); WriteLn(Length(s), ' [', s, ']');
  ss := 'short'; Delete(ss, 1, 1); Insert('X', ss, 3); WriteLn(Length(ss), ' [', ss, ']');
end.
