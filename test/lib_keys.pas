program lib_keys;
{ Drives the real key-reading path (ScreenWaitKey: blocking read + bounded
  escape-sequence gather + decode) from piped stdin, printing each key code.
  Catches input-path bugs the pure-decoder test cannot (e.g. a clobbered read
  count, or over-reading the next key into an escape sequence). }
uses screen;
var k: Integer;
begin
  repeat
    k := ScreenWaitKey;
    if k <> KEY_NONE then writeln(k);
  until k = KEY_NONE;
end.
