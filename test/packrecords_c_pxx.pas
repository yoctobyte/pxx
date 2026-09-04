{ {$PACKRECORDS C} against the gcc oracle, both rows printed by one program.

  LINE 1 is the claim: `c` must equal what gcc lays out for the same struct, on
  every target -- it is not a synonym for any fixed N, because C's rule is
  per-field natural alignment under the platform ABI and i386 caps an 8-byte
  scalar at 4 where x86-64 does not.

  LINE 2 IS THE POSITIVE CONTROL AND IT IS NOT OPTIONAL. The failure mode this
  file guards is a directive that is ACCEPTED AND IGNORED: if `{$packrecords c}`
  silently did nothing, line 1 would still match gcc, because pxx's default
  layout already agrees with gcc. Only a second row under a directive whose
  answer must DIFFER can tell "the directive worked" from "the directive was
  discarded". {$packrecords 1} is that row -- it must not equal line 1.
  feature-p-packrecords-c-directive }
program packrecords_c_pxx;
{$packrecords c}
type SC = record a: Char; b: Double; c: SmallInt; d: LongInt; e: Char; end;
{$packrecords 1}
type S1 = record a: Char; b: Double; c: SmallInt; d: LongInt; e: Char; end;
var rc: SC; r1: S1;
begin
  WriteLn(PtrUInt(@rc.a) - PtrUInt(@rc), ' ', PtrUInt(@rc.b) - PtrUInt(@rc), ' ',
          PtrUInt(@rc.c) - PtrUInt(@rc), ' ', PtrUInt(@rc.d) - PtrUInt(@rc), ' ',
          PtrUInt(@rc.e) - PtrUInt(@rc), ' ', SizeOf(SC));
  WriteLn(PtrUInt(@r1.a) - PtrUInt(@r1), ' ', PtrUInt(@r1.b) - PtrUInt(@r1), ' ',
          PtrUInt(@r1.c) - PtrUInt(@r1), ' ', PtrUInt(@r1.d) - PtrUInt(@r1), ' ',
          PtrUInt(@r1.e) - PtrUInt(@r1), ' ', SizeOf(S1));
end.
