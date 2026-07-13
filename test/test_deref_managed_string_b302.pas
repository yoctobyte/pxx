{ `^string` — a pointer to a MANAGED string. Reading `p^` SEGFAULTED.

  `@s` yielded the string's HANDLE (its heap data pointer), not the address of the VARIABLE.
  That is because IR_LEA on a scalar AnsiString deliberately LOADS the slot rather than taking
  its address -- the slot holds a heap pointer, and every consumer that wants "the string's
  bytes" (a by-ref pass, C interop) wants exactly that.

  But it made `@s` mean something other than "@". So `p: ^string; p := @s; p^` read the
  string's first 8 bytes AS IF they were a handle, and died.

  `@` on a managed-string variable now yields AN_SLOTADDR -- "the variable's own slot, no
  auto-deref", which is precisely what @ means and what the node already existed for. Nothing
  else moves: the by-ref and lvalue-write paths do not go through AN_ADDR.

  Length(p^) had a workaround built ON the old meaning -- it lowered `p` and merely RETAGGED it
  as the string, correct only while p WAS the handle. It now loads through the slot. Without
  that it silently returned 0. }
program test_deref_managed_string_b302;
type PStr = ^string;
procedure SetIt(p: PStr; const v: string);
begin
  p^ := v;                        { write a managed string THROUGH a pointer }
end;
var s, t: string; p: PStr;
begin
  s := 'orig';
  p := @s;
  writeln('read      : ', p^);
  p^ := 'changed';
  writeln('after write: ', s);
  SetIt(@s, 'via proc');
  writeln('via proc  : ', s);
  t := p^;                        { read back into another managed string }
  writeln('copied    : ', t, ' len=', Length(t));
  { the by-ref path must be unaffected }
  writeln('len via ^ : ', Length(p^));
end.
