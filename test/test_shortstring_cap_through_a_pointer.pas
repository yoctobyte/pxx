{ The truncating `string[N]` clamp is derived per LHS SHAPE, in a chain that has
  grown one arm per discovery: the array SYMBOL arm, then the array FIELD arm,
  and now `p^[i]` where p points at an array of string[N]. Without it the store
  copied the SOURCE length and wrote past the element -- and read back with a
  length that is not the slot's.

  The `p^[i]` arm needed NO new carrier, which is the whole finding:
  SymPtrElemStrCap already holds that N and the INDEX path has read it for the
  element SLOT STRIDE all along. The carrier was present and the reader absent.

  THE FOURTH ARM, `p^ := <too long>` on a bare `^string[N]`, IS THE ONE THAT
  NEEDED A CARRIER and is now here as `ptrdirect`. The parser recorded the
  pointee's KIND and nothing recorded its N, so the store copied the SOURCE
  length: sixteen characters into an eight-character slot, on x86-64, i386,
  aarch64, arm32 and riscv32 in both modes -- ten cells. That N now rides
  LastTypePointerStrCap from the one general `^T` arm, through AliasPtrStrCap
  (an alias is where a pointer type is almost always spelled), into
  SymPtrElemStrCap via SetPtrElemArrayInfo, which is the one procedure all four
  allocators call.

  EVERY ROW ASSERTS A NEIGHBOUR, and that is the point of the file rather than
  a flourish: this defect writes PAST the slot, so a length check alone passes
  over a clamp that bounded the length word and not the copy. `ptrdirect`'s
  neighbour is `guard`, which came back EMPTY in the default mode before the fix
  (its 8-byte length prefix overwritten) and printed hundreds of bytes of
  adjacent memory under -dPXX_SHORTSTRING.

  Every row must print 8 and match FPC.
  bug-a-a-store-through-a-pointer-loses-the-shortstring-capacity-clamp }
program test_shortstring_cap_through_a_pointer;
type
  TS   = string[8];
  TA   = array[0..1] of TS;
  PArr = ^TA;
  TR   = record a: TA; tail: LongInt; end;
  PStr = ^TS;
const LONG = 'abcdefghijklmnop';
var
  s: TS; a: TA; pa: PArr; r: TR; pr: ^TR;
  d: TS; guard: TS; ps: PStr;
begin
  { the shapes that already clamped -- here so a fix cannot regress them }
  s := LONG;                      WriteLn('sym       ', Length(s), ' ', s);
  a[0] := LONG;                   WriteLn('elem      ', Length(a[0]), ' ', a[0]);
  r.a[0] := LONG;                 WriteLn('fieldelem ', Length(r.a[0]), ' ', r.a[0]);

  { the arm this test is named for: through a pointer TO THE ARRAY }
  a[1] := 'keep';
  pa := @a;
  pa^[0] := LONG;
  WriteLn('ptrelem   ', Length(a[0]), ' ', a[0]);

  { the neighbour is the assertion that the clamp bounded the WRITE and not just
    the length word -- an unclamped 16-char copy runs into element 1 }
  WriteLn('neighbour ', a[1]);

  { same shape one level in, through a pointer to the RECORD holding the array.
    tail catches a copy that ran past the last element into the next field. }
  r.tail := 12345;
  r.a[1] := 'zz';
  pr := @r;
  pr^.a[0] := LONG;
  WriteLn('recptrelem ', Length(r.a[0]), ' ', r.a[0], ' n=', r.a[1], ' tail=', r.tail);

  { the arm that needed the carrier: the pointee IS the string, not an array of
    them. `guard` is declared right after `d` so an unclamped 16-char copy runs
    into it. }
  d := ''; guard := 'GUARD';
  ps := @d;
  ps^ := LONG;
  WriteLn('ptrdirect ', Length(d), ' ', d, ' g=', guard);
end.
