program lib_strpchar;
{ Smoke for the SysUtils routines added for Synapse (feature-synapse-compile-check):
  StrLCopy, StrLComp, Sleep, Move (overlap-safe), FillChar, IntToHex, StringOfChar. }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
end;

function MoveFillOk: Boolean;
var a: array[0..9] of Byte; i: Integer;
begin
  for i := 0 to 9 do a[i] := i + 1;          { 1..10 }
  Move(a[0], a[3], 4);                        { overlap up -> 1 2 3 1 2 3 4 8 9 10 }
  Result := (a[3] = 1) and (a[4] = 2) and (a[5] = 3) and (a[6] = 4) and (a[7] = 8);
  FillChar(a[0], 5, 0);                       { 0 0 0 0 0 3 4 8 9 10 }
  Result := Result and (a[0] = 0) and (a[4] = 0) and (a[5] = 3);
end;

var
  dst: array[0..15] of Char;
  r: PChar;
begin
  { StrLCopy truncates at MaxLen and #0-terminates; returns Dest. }
  r := StrLCopy(@dst[0], 'hello world', 5);
  SayBool('strlcopy-ret', r = @dst[0]);
  SayBool('strlcopy-trunc', (dst[0] = 'h') and (dst[4] = 'o') and (dst[5] = #0));

  { Source shorter than MaxLen: copies up to its #0. }
  StrLCopy(@dst[0], 'ab', 10);
  SayBool('strlcopy-short', (dst[0] = 'a') and (dst[1] = 'b') and (dst[2] = #0));

  { StrLComp: equal within MaxLen, difference, and #0 stop. }
  SayBool('strlcomp-eq', StrLComp('abcZ', 'abcX', 3) = 0);
  SayBool('strlcomp-lt', StrLComp('abc', 'abd', 3) < 0);
  SayBool('strlcomp-gt', StrLComp('abd', 'abc', 3) > 0);

  { Sleep returns after at least the requested delay (smoke: just runs). }
  Sleep(1);
  SayBool('sleep', True);

  { Move (overlap-safe) + FillChar. }
  SayBool('move-fillchar', MoveFillOk);

  { IntToHex / StringOfChar (FPC SysUtils). }
  SayBool('inttohex-ff', IntToHex(255, 2) = 'FF');
  SayBool('inttohex-pad', IntToHex(10, 4) = '000A');
  SayBool('stringofchar', StringOfChar('x', 3) = 'xxx');
  SayBool('stringofchar-0', StringOfChar('y', 0) = '');
end.
