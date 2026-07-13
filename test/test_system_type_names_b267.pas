program test_system_type_names_b267;
{ System type names that were NEVER recognised. Until the unknown-name fallback was closed
  (b266) each of these silently became a 4-byte Integer — which for TDateTime (a Double!)
  and for the string aliases is badly wrong, not merely mis-sized. With the fallback closed
  they would instead be hard errors, so they have to actually exist.

  A user or RTL declaration still wins (FindTypeAlias is consulted first). TDateTime and
  Currency deliberately match what lib/rtl/sysutils already declares them as, so a program
  that uses sysutils and one that does not agree. }
var
  w: WideChar;        { 2 bytes, not 4 }
  c: Comp;            { 8 }
  d: TDateTime;       { a DOUBLE — was a 4-byte Integer }
  cu: Currency;
  si: SizeInt;
  su: SizeUInt;
  pw: PWideChar;
  u: UTF8String;
  r: RawByteString;
  lb: LongBool;       { C-ABI booleans keep their WIDTH }
  wb: WordBool;
  bb: ByteBool;
begin
  writeln('WideChar=', SizeOf(w));
  writeln('Comp=', SizeOf(c));
  writeln('TDateTime=', SizeOf(d));
  writeln('Currency=', SizeOf(cu));
  writeln('SizeInt=', SizeOf(si), ' SizeUInt=', SizeOf(su));
  writeln('PWideChar=', SizeOf(pw));
  writeln('bools=', SizeOf(lb), ' ', SizeOf(wb), ' ', SizeOf(bb));

  { TDateTime must actually behave as a floating-point value }
  d := 1.5;
  d := d + 0.25;
  writeln('dt=', d:0:2);

  u := 'hi';
  r := u;
  writeln('str=', u, ' ', r);
end.
