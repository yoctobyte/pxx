{ The truncating `string[N]` clamp is derived per LHS SHAPE, in a chain that has
  grown one arm per discovery: the array SYMBOL arm, then the array FIELD arm,
  and now `p^[i]` where p points at an array of string[N]. Without it the store
  copied the SOURCE length and wrote past the element -- and read back with a
  length that is not the slot's.

  The `p^[i]` arm needed NO new carrier, which is the whole finding:
  SymPtrElemStrCap already holds that N and the INDEX path has read it for the
  element SLOT STRIDE all along. The carrier was present and the reader absent.

  Every row here must print 8 and match FPC. `p^ := <too long>` on a bare
  ^string[N] is DELIBERATELY ABSENT: it still copies 16 and needs a carrier that
  does not exist yet --
  bug-a-a-store-through-a-pointer-loses-the-shortstring-capacity-clamp.

  bug-a-a-store-through-a-pointer-loses-the-shortstring-capacity-clamp (partial) }
program test_shortstring_cap_through_a_pointer;
type
  TS   = string[8];
  TA   = array[0..1] of TS;
  PArr = ^TA;
  TR   = record a: TA; tail: LongInt; end;
const LONG = 'abcdefghijklmnop';
var
  s: TS; a: TA; pa: PArr; r: TR; pr: ^TR;
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
end.
