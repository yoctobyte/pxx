program margfailstr;
{$mode objfpc}
{ The negative half the NARROW allowlist could not reach. Its two guard lines
  only let the check run when the argument was already a pointer or a class AND
  the parameter was ordinal/float/string-ish, so a STRING LITERAL given to an
  Integer parameter fell straight through and the call was accepted.

  fpc 3.2.2 on this exact line:
    Error: Incompatible type for arg no. 1: Got "Constant String", expected "LongInt"
  pxx before the widening: ACCEPTED, with no diagnostic at all.

  The identical FREE procedure has always refused it -- that asymmetry is the
  whole subject of
  refactor-p-the-overload-probe-still-cannot-answer-two-argument-shapes. }
type
  TCls = class
    constructor Make;
    procedure M(a: Integer);
  end;

constructor TCls.Make; begin end;
procedure TCls.M(a: Integer); begin WriteLn('M ', a); end;

var t: TCls;
begin
  t := TCls.Make;
  t.M('not an integer');
end.
