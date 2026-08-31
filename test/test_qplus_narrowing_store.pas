program test_qplus_narrowing_store;
{ {$Q+} must raise Runtime error 215 when a checked binop's result does not fit
  the destination. THE CHECK LIVES AT THE NARROWING STORE, not at the binop:
  Pascal widens Q-tagged arithmetic to Int64 in the frontend, so `Integer +
  Integer` reaches codegen as a 64-bit binop that cannot overflow, and the wrap
  happens when the 64-bit value is stored into a 4/2/1-byte slot.

  That is measured, not assumed -- a canary Error() planted in a 32-bit
  checked-add arm of the xtensa binop emitter was never reached by any {$Q+}
  program. Anyone "fixing" a missing overflow trap by adding a checked-add arm
  to a binop emitter is editing dead code.

  xtensa had no check at either place and wrapped SILENTLY on every shape below
  -- printing -2147483648, 144, -56, 54464 and carrying on -- while the other
  five targets trapped. Shape is selected by ARGUMENT COUNT so each run enters a
  different branch; shape 5 is the CONTROL and must NOT trap.
  bug-a-xtensa-has-no-q-plus-overflow-check-emitter-so-it-wraps-silently }
{$Q+}
var
  i, j, k: Integer;
  b: Byte;
  sh: ShortInt;
  w: Word;
  sel: Integer;
begin
  sel := ParamCount;
  WriteLn('start');
  i := 2147483647; j := 1 + sel;
  if sel = 0 then begin k := i + j; WriteLn('no trap k=', k); end
  else if sel = 1 then begin i := -2147483647 - 1; j := 1; k := i - j; WriteLn('no trap k=', k); end
  else if sel = 2 then begin b := 200; b := b + b; WriteLn('no trap b=', b); end
  else if sel = 3 then begin sh := 100; sh := sh + sh; WriteLn('no trap sh=', sh); end
  else if sel = 4 then begin w := 60000; w := w + w; WriteLn('no trap w=', w); end
  else begin i := 5; j := 3; k := i + j; b := 3; b := b + b; WriteLn('ok k=', k, ' b=', b); end;
end.
