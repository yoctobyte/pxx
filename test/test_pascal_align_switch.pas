program test_pascal_align_switch;
{ {$A n} / {$A+} / {$A-} are the Turbo/Delphi SHORT SPELLING of {$PACKRECORDS}.
  pxx ignored them entirely until 2026-09-04, so a unit opening with {$A8} —
  or worse {$A1} — got pxx's default layout while fpc gave it another, with no
  diagnostic. Found by censusing fpc 3.2.2's own sources for directive words
  this compiler does not know: {$A8} came back as an UNKNOWN directive, i.e.
  reported as a typo, on code fpc accepts.

  Every row below is fpc 3.2.2's own answer, measured. The rows that carry the
  assertion are A1/A2/A4/A+/A-, because those DIFFER from the default — A8 and
  A16 equal it, so on their own they would pass against a compiler that still
  ignored the directive. }
type
  TA = record a: Byte; b: Int64; c: Byte; end;
{$A1}
  T1 = record a: Byte; b: Int64; c: Byte; end;
{$A2}
  T2 = record a: Byte; b: Int64; c: Byte; end;
{$A4}
  T4 = record a: Byte; b: Int64; c: Byte; end;
{$A8}
  T8 = record a: Byte; b: Int64; c: Byte; end;
{$A16}
  T16 = record a: Byte; b: Int64; c: Byte; end;
{$A+}
  TPlus = record a: Byte; b: Int64; c: Byte; end;
{$A-}
  TMinus = record a: Byte; b: Int64; c: Byte; end;
{$A8}

procedure Show(const tag: AnsiString; sz, off: Integer);
begin
  writeln(tag, ' ', sz, ' ', off);
end;

var
  ra: TA; r1: T1; r2: T2; r4: T4; r8: T8; r16: T16; rp: TPlus; rm: TMinus;
begin
  Show('default', SizeOf(TA), PtrUInt(@ra.b) - PtrUInt(@ra));
  Show('a1', SizeOf(T1), PtrUInt(@r1.b) - PtrUInt(@r1));
  Show('a2', SizeOf(T2), PtrUInt(@r2.b) - PtrUInt(@r2));
  Show('a4', SizeOf(T4), PtrUInt(@r4.b) - PtrUInt(@r4));
  Show('a8', SizeOf(T8), PtrUInt(@r8.b) - PtrUInt(@r8));
  Show('a16', SizeOf(T16), PtrUInt(@r16.b) - PtrUInt(@r16));
  Show('aplus', SizeOf(TPlus), PtrUInt(@rp.b) - PtrUInt(@rp));
  Show('aminus', SizeOf(TMinus), PtrUInt(@rm.b) - PtrUInt(@rm));
end.
