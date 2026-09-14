program test_a_threadvar_program_does_not_lower_ordinary_symbols_through_gs;
{ bug-a-a-symbol-a-threadvar-program-never-declared-is-lowered-as-a-threadvar.

  RewriteThreadVarRefs arms on `TlsUserUsed > 0` -- on the program declaring ANY
  threadvar -- and then rewrites every AN_IDENT whose SymTlsOffset is >= 0 into a
  read through the thread block. -1 is the not-a-threadvar sentinel, and until
  2026-09-14 only AllocVar wrote it: AllocParam, AllocArray, AllocDynArray and
  AddConst left EnsureSymCapacity's SetLength ZERO, and 0 is a perfectly valid
  offset as far as that test is concerned. So an ordinary parameter could be
  lowered into a dereference of the thread block's first word.

  THE SYMPTOM IS A WRONG VALUE, NOT A CRASH, which is why it survived: measured
  on pin v408, this program prints s=4369466 where 78 is the answer. It reached
  a crash only in test_a_threadvar_is_per_thread, where the poisoned symbol
  happened to be an array INDEX.

  WHY IT NEEDS A UNIT AND SOME PADDING, and this is the fragile part: capacity
  never shrinks across the per-frontend SymCount reset, so a slot is -1 only if
  a previous pass's AllocVar left it that way. Whether a given parameter lands
  on a virgin slot is therefore symbol-index arithmetic. Measured against the
  unfixed compiler over padding sizes 0..24: 0 and 1 pass, 2..24 all leak -- a
  broad plateau, not a knife edge, so this fixture keeps witnessing the defect
  across a fair amount of RTL drift. It is still a WITNESS and not the
  guarantee; the guarantee is that all five Alloc* paths now write the sentinel.

  NO THREADS: the rewrite is a compile-time pass and one thread observes it.
  test_a_threadvar_is_per_thread covers the runtime half. }

uses palthread;

threadvar
  tv: LongInt;

const
  PAD0 = 0;
  PAD1 = 1;
  PAD2 = 2;
  PAD3 = 3;

var
  Arr: array[0..7] of LongInt;
  Dyn: array of LongInt;

function Twelve(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12: LongInt): LongInt;
begin
  Twelve := a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11 + a12;
end;

function AlsoTwelve(b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12: LongInt): LongInt;
begin
  AlsoTwelve := b1 + b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9 + b10 + b11 + b12;
end;

var
  i, sa, sb, sarr, sdyn: LongInt;

begin
  tv := 7;

  sa := Twelve(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);
  sb := AlsoTwelve(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12);

  for i := 0 to 7 do Arr[i] := i + 1;
  sarr := 0;
  for i := 0 to 7 do sarr := sarr + Arr[i];

  SetLength(Dyn, 8);
  for i := 0 to 7 do Dyn[i] := i + 1;
  sdyn := 0;
  for i := 0 to 7 do sdyn := sdyn + Dyn[i];

  WriteLn('params=', sa, ' ', sb);
  WriteLn('consts=', PAD0 + PAD1 + PAD2 + PAD3);
  WriteLn('array=', sarr);
  WriteLn('dynarray=', sdyn);
  WriteLn('threadvar=', tv);
  if (sa = 78) and (sb = 78) and (PAD0 + PAD1 + PAD2 + PAD3 = 6)
     and (sarr = 36) and (sdyn = 36) and (tv = 7) then
    WriteLn('NO GS LEAK')
  else
    WriteLn('GS LEAK');
end.
