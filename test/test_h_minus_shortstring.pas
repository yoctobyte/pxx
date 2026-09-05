{ {$H-} / {$LONGSTRINGS OFF}: a bare `string` is a 256-byte ShortString.
  Line 3 of fpc 3.2.2's own fpcdefs.inc, so it is the string model every unit
  of the FPC compiler is built with.

  BOTH ARMS ARE ASSERTED and that is the point. pxx's default bare `string` is
  already the managed one, so the {$H+} rows would pass even if the directive
  were accepted and discarded -- which is the state this test was written to
  end. Only the {$H-} rows separate "implemented" from "swallowed".

  The directive is also POSITIONAL: it runs in the LEX pass, so a global read at
  parse time would hand the LAST {$H} in the file to every declaration in it.
  The file therefore switches back to {$H+} half way down, and the rows below
  that point must go back to 8. A file with a single directive cannot fail on
  that difference.

  Verified row-for-row against fpc 3.2.2 on x86-64.
  feature-p-h-minus-makes-a-bare-string-a-shortstring }
program test_h_minus_shortstring;

{$H-}
type
  TShortRec = record s: string; n: LongInt; end;
  TShortAlias = string;
var gShort: string; gShortA: TShortAlias; rShort: TShortRec;

{$H+}
type
  TLongRec = record s: string; n: LongInt; end;
var gLong: string; rLong: TLongRec;

procedure PShort;
{$H-}
var l: string;
begin
  l := 'in-proc';
  WriteLn('local H- ', SizeOf(l), ' ', l, ' ', Length(l));
end;

begin
  gShort := 'abc'; gShortA := 'de'; gLong := 'xyz';
  WriteLn('var    H- ', SizeOf(gShort));
  WriteLn('alias  H- ', SizeOf(gShortA));
  WriteLn('rec    H- ', SizeOf(TShortRec));
  WriteLn('var    H+ ', SizeOf(gLong));
  WriteLn('rec    H+ ', SizeOf(TLongRec));
  { the values must survive either model }
  WriteLn('cat       ', gShort + gShortA, ' ', Length(gShort + gShortA));
  WriteLn('mix       ', gShort + gLong);
  WriteLn('copy      ', Copy(gShort, 2, 2), ' ', Pos('bc', gShort));
  rShort.s := 'inrec'; rShort.n := 7;
  rLong.s := 'inrec2'; rLong.n := 8;
  WriteLn('recval    ', rShort.s, ' ', rShort.n, ' ', rLong.s, ' ', rLong.n);
  PShort;
end.
