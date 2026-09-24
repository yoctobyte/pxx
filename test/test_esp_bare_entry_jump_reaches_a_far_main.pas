{ A bare esp32s3 program whose main body starts more than 128 KiB past the
  entry stub BEFORE dead code is dropped. The entry jump is patched then, and
  bare used xtensa's short `j` (+-128 KiB) on the argument that bare images
  are small -- true after DCE, not when the jump is measured. The unused
  Double plus the AnsiString concat pull enough unit code to put main 131401
  bytes out, and the build was refused ("j displacement 131401 is outside the
  encodable range"). Bare now takes the long form the IDF path uses.

  Boots under qemu-system-xtensa (test-esp-bare) and must print `str -4095`
  on the UART, so the row proves the long jump lands on main, not just that
  the image builds. }
program test_esp_bare_entry_jump_reaches_a_far_main;
procedure PutC(c: Integer);
begin
  PByte(Int64($60000000))^ := Byte(c);
end;
procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;
var s: AnsiString; n: Int64; d: Double;
begin
  n := -4095;
  Str(n, s);
  PutS('str ' + s);
  while True do ;
end.
