program r64;
{$mode objfpc}
{ {$R+} across the 64-BIT boundary. Every narrower destination was already
  checked; Int64 and QWord are not NARROWER than the compute width, so both fell
  out of IRWrapRangeChk's case and got no check at all -- `q := s` with a
  negative s stored the two's-complement bits in silence.

  The check owed here is a SIGN check, and it is source-conditional: the value
  reaches PXXRangeChkI64 as an Int64, so a negative signed source and a QWord
  above High(Int64) both arrive negative, while a QWord-to-QWord copy above 2^63
  arrives negative too and must NOT raise. That last row is why this file counts
  both directions -- a blanket lo=0 on a QWord destination passes every "caught"
  row and breaks a legal same-type copy. }
uses sysutils;
var s: shortint; i: smallint; l: longint; b: byte; c: cardinal;
    q, q2: qword; t: int64; caught, lax: Integer;
begin
  caught := 0; lax := 0;
  {$R+}
  { MUST raise: a negative signed value has no QWord representation. }
  s := -128;
  try q := s; except on erangeerror do inc(caught); end;
  i := -32768;
  try q := i; except on erangeerror do inc(caught); end;
  l := -maxlongint-1;
  try q := l; except on erangeerror do inc(caught); end;
  t := -1;
  try q := t; except on erangeerror do inc(caught); end;
  { MUST raise: a QWord above High(Int64) has no Int64 representation. }
  q := qword($ffffffff00000000);
  try t := q; except on erangeerror do inc(caught); end;

  { MUST NOT raise -- the controls. The first is the one a blanket lo=0 breaks. }
  q2 := qword($ffffffff00000000);
  try q := q2; inc(lax); except on erangeerror do ; end;
  c := $ffffffff;
  try q := c; inc(lax); except on erangeerror do ; end;
  b := 255;
  try q := b; inc(lax); except on erangeerror do ; end;
  l := 5;
  try q := l; inc(lax); except on erangeerror do ; end;
  l := -5;
  try t := l; inc(lax); except on erangeerror do ; end;
  q2 := 10;
  try q := q2 + 1; inc(lax); except on erangeerror do ; end;
  { QWord arithmetic above 2^63: the binop result must not read as signed. }
  q2 := qword($ffffffff00000000);
  try q := q2 + 1; inc(lax); except on erangeerror do ; end;

  { and the copy must be a COPY -- a guard that raises correctly can still
    mangle the value it lets through. }
  q := qword($ffffffff00000000);
  if q = qword($ffffffff00000000) then write('copy-ok ') else write('copy-BAD ');
  writeln('caught=', caught, ' lax=', lax);
end.
