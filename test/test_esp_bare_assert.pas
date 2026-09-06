program test_esp_bare_assert;
{ `Assert` on the bare-metal profile. Nothing here ran before
  bug-a-assert-is-undefined-on-the-esp-bare-profile: the source did not COMPILE
  for --esp-profile=bare at all, on either chip, because bare pulls no `builtin`
  and so has no `__pxxAssert` for the parser's soft-alias to bind to. A five-line
  program answered `undefined variable (Assert)`.

  Two properties, and the second is the one a compile check cannot see:

    * a PASSING assertion is silent and execution continues;
    * a FAILING one prints FPC's composed message -- the message REPLACING
      'Assertion failed' rather than following it, position appended, period
      from the printer -- and then stops.

  The output is diffed against the x86-64 oracle, so the device and the desktop
  must agree byte for byte. That is what makes this row able to fail: a no-op
  Assert prints nothing where the oracle prints the message AND reaches the tail
  line the oracle never reaches, so it differs at both ends.

  `writeln` IS A NO-OP ON THIS PROFILE (docs/targets/esp32.md:70) -- there is no
  console. That is exactly why the first fix for the ticket above compiled on
  both chips and printed nothing when the assertion fired, a silent Halt(227),
  and why `espassert` writes the failure to the UART0 TX FIFO itself. This test
  hand-rolls the same MMIO write for its own output, like every other program in
  this suite. }

procedure PutC(code: Integer);
begin
{$ifdef PXX_ESP_BARE}
  { UART0 TX FIFO, same address on esp32c3 and esp32s3 -- defs.inc:1847. }
  PByte(Int64($60000000))^ := Byte(code);
{$else}
  Write(Chr(code));
{$endif}
end;

procedure PutS(const s: AnsiString);
var i: Integer;
begin
  for i := 1 to Length(s) do PutC(Ord(s[i]));
end;

var i: Integer;
begin
  i := 1;
  Assert(i = 1);
  PutS('passing assert is silent'#10);
  Assert(i = 1, 'this message must not appear');
  PutS('a passing assert ignores its message'#10);
  Assert(i = 2, 'boom');
  PutS('NOT REACHED'#10);
end.
