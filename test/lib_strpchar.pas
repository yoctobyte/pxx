program lib_strpchar;
{ Smoke for the SysUtils PChar/strings routines + Sleep added for Synapse's
  synafpc (feature-synapse-compile-check): StrLCopy, StrLComp, Sleep. }
uses sysutils;

procedure SayBool(const tag: string; b: Boolean);
begin
  if b then writeln(tag, '=ok') else writeln(tag, '=FAIL');
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
end.
