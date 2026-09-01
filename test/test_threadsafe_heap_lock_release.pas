program test_threadsafe_heap_lock_release;
{ The heap lock's RELEASE is `mov dword [@glob], 0` -- C7 /0, an absolute
  memory operand with an imm32 TRAILING the displacement. When EmitGlobRef
  learned to emit rip-relative operands it measured "no site has a trailing
  immediate" over five --emit-obj objects, none of which used --threadsafe, so
  the population could not contain this shape. The release then wrote four
  bytes past the lock word: the lock was never freed, the next acquire spun
  forever, and a threaded program hung at its first join.

  This pins it SINGLE-THREADED and in under a second, because the defect does
  not need threads -- it needs a second acquire. Reintroduce the bug (make
  GlobRefTrailingImm answer 0 for $C7) and this program hangs; that control was
  run, not assumed.

  feature-a-x86-64-object-output-is-position-dependent }
{$THREADSAFE ON}
var
  p, q: ^Integer;
  i: Integer;
begin
  for i := 1 to 3 do
  begin
    p := GetMem(8);
    q := GetMem(8);
    p^ := i;
    q^ := i * 2;
    if p^ + q^ <> i * 3 then
    begin
      WriteLn('THREADSAFE HEAP LOCK BAD: ', p^, ' ', q^);
      Halt(1);
    end;
    FreeMem(q);
    FreeMem(p);
  end;
  WriteLn('THREADSAFE HEAP LOCK OK');
end.
