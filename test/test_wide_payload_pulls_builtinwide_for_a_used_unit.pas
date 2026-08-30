{$define PXX_WIDE_PAYLOAD}
program test_wide_payload_pulls_builtinwide_for_a_used_unit;
{ Under PXX_WIDE_PAYLOAD, a program that USES a unit naming WideString while
  never naming it itself.

  This was `compiler error: UTF-16 width conversion needs builtinwide
  (widestring with no RTL?)` — from a four-line program with no --no-rtl in
  sight. The builtinwide unit is pulled by a token scan in pasparser_prog.inc,
  and that scan sees the PROGRAM's tokens and not its used units': lib/rtl's
  sysutils.pas has widestring functions, so under the define its own body needed
  a transcoder the driver had decided nothing could reach. Adding `var w:
  WideString` to the PROGRAM made the identical build succeed, which is what
  identified the SCOPE of the scan as the cause rather than the unit.

  Without the define it cannot happen — widestring IS ansistring, so no width
  conversion is ever synthesised. The define gated its own blocker, which is why
  it went unmet, and why this test carries the define at the top: delete that
  line and the test passes for the wrong reason.

  The body deliberately does NOT mention WideString: naming it is what used to
  be required, so a test that named it would pass on the broken compiler. It
  calls SysUtils instead — one string function, so the unit is really linked and
  not merely named. }
uses SysUtils;
var s: AnsiString;
begin
  s := UpperCase('ok');
  WriteLn('wide-unit ', s);
end.
