{ A nested routine is lambda-LIFTED: its tokens are copied out to a side buffer,
  deleted from the stream, and appended back at the end much later. That stash
  carried the TRawToken and NONE of the thirteen token-parallel channels, and the
  in-place delete moved Tokens[] by hand instead of through RemoveTokens, so it
  never reached ShiftTokParallel either. Two movers, one missing list.

  THE DIRECTIVE STATES ARE THE HALF THAT IS NOT COSMETIC and they are what this
  fixture asserts. Measured 2026-09-08 before the fix: `{$R+}` was NOT in force
  inside a lifted nested routine's body -- an out-of-range store went through and
  the program carried on, where fpc 3.2.2 raises Runtime error 201. The lifted
  body ran under whatever directive state happened to sit at the appended token
  indices.

  A SUBRANGE store, not an array index, on purpose: under {$R-} the row has to
  print a value rather than corrupt memory, so the two arms differ by a
  diagnostic and not by luck. Both arms are LIFTED (each nested routine captures
  nothing, but the lift is unconditional), and the {$R-} arm is the control --
  without it a fix that turned range checking on everywhere would pass.

  The other half, the two SPELLING channels, is a compile-time diagnostic and
  cannot be a row of an output comparison; the Makefile asserts it separately
  against test/test_a_lifted_nested_routine_keeps_its_token_channels_diag.pas,
  whose deliberate syntax error must name the token it is actually at.

  Expected values are the fpc 3.2.2 oracle.
  bug-p-after-a-nested-routine-is-lifted-a-later-syntax-error-names-the-wrong-token }
program test_a_lifted_nested_routine_keeps_its_token_channels;

{$mode objfpc}

type TSmall = 1..9;

var g: LongInt;

{$R-}
procedure Unchecked(k: LongInt);
  procedure Inner(n: LongInt);
  var v: TSmall;
  begin
    v := n;                       { out of 1..9, and {$R-} here }
    WriteLn('unchecked ', v);
  end;
begin
  Inner(k);
end;

{$R+}
procedure Checked(k: LongInt);
  procedure Inner(n: LongInt);
  var v: TSmall;
  begin
    v := n;                       { the SAME store, under {$R+} -- must trap }
    WriteLn('checked-not-reached ', v);
  end;
begin
  Inner(k);
end;
{$R-}

begin
  g := 20;
  Unchecked(g);
  WriteLn('before-checked');
  Checked(g);
  WriteLn('after-checked-not-reached');
end.
