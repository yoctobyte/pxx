program test_esp_bare_str;
{ Bare-metal `Str` on both ESP families, booted under the Espressif qemu and
  diffed against the x86-64 oracle running the same source
  (feature-a-non-float-str-on-the-bare-esp-profile).

  WHY A RUNTIME ROW AND NOT A COMPILE ROW. `Str` was refused at COMPILE time on
  this profile for every type, so the tempting fixture is "it compiles now". That
  fixture would pass over a `Str` that returns the empty string -- and this
  suite has already been bitten by exactly that: espassert.pas's first draft
  compiled on both chips and PRINTED NOTHING, and only the serial bytes told the
  difference. So every row here asserts TEXT.

  WHY THESE VALUES. Each is chosen so a correct answer differs from the failure
  value, which for a string formatter is `''`:
    - Low(Int64) is the case StrInt's own body calls out as having once produced
      just "-", so it separates a working negative path from a truncated one.
    - QWord high is the row StrQWord exists for: StrInt printed values >= 2^63
      with a minus sign, so an unsigned that routes to the signed formatter is
      visible here and nowhere else.
    - A field width is padded on the LEFT, so `[    42]` distinguishes a real
      pad from both `[42]` and `[]`.
  A row that merely printed a non-empty string would pass for a formatter that
  ignored its argument; every value above is one no other row produces.

  NOT TESTED HERE, DELIBERATELY: Str of a float. It stays refused on bare,
  because StrFloat needs PxxSciDigits17 and therefore softfloat, which the bare
  path skips so a float-free MCU program does not pay ~54-64 KB of flash. That
  boundary has its own compile-time control in the ticket; asserting it here
  would need a second program, since a refused compile has no UART output.

  The PutC/PutS scaffolding is test_esp_bare.pas's, unchanged. }

procedure PutC(code: Integer);
begin
{$ifdef PXX_ESP_BARE}
  { Bare metal: straight into the UART0 TX FIFO. }
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

var s: AnsiString; n: Int64; q: QWord; c: Char; b: Boolean; w: AnsiString;
begin
  n := -4095;                 Str(n, s);    PutS('int=' + s);            PutC(10);
  n := Low(Int64);            Str(n, s);    PutS('low=' + s);            PutC(10);
  q := 18446744073709551615;  Str(q, s);    PutS('qw=' + s);             PutC(10);
  c := 'z';                   Str(c, s);    PutS('chr=' + s);            PutC(10);
  b := False;                 Str(b:8, s);  PutS('bool=[' + s + ']');    PutC(10);
  n := 42;                    Str(n:6, s);  PutS('wid=[' + s + ']');     PutC(10);
  w := 'hi';                  Str(w:5, s);  PutS('strw=[' + s + ']');    PutC(10);
{$ifdef PXX_ESP_BARE} while True do ; {$endif}
end.
