{ `@dy` on a dynamic array yields the address of the VARIABLE, not its handle.

  It used to yield the handle, so `@dy`, `Pointer(dy)` and `@dy[0]` were all one
  address. That is a stale pointer, not a cosmetic difference: `p := @dy`
  captured the buffer that existed at @-time, so a SetLength that MOVED the
  block left p reading freed memory -- silently, compiling clean. Measured
  before the fix: after `SetLength(dy, 9)`, `Length(p^)` still answered 5 off the
  old buffer, `p^[0]` read 0, `p^[1] := 7` wrote past the array, and
  `p^ := other` segfaulted.

  Managed strings had already been corrected the same way (`@s` -> the slot), and
  dynamic arrays are the same concept: a managed handle in a slot. The string
  rows are here beside the array ones because the point of the fix is that there
  is ONE rule for what `@` means over a managed value.

  The identity rows are the load-bearing ones: `@dy = Pointer(dy)` being FALSE is
  the whole bug, and it is the row that cannot be got right by accident.

  Every row measured against fpc 3.2.2 (-Mobjfpc -O1).

  NOT covered, and refused with a diagnostic that says so: `SetLength(p^, n)`.
  fpc accepts it; the dyn-array SetLength codegen here is symbol-based in all six
  backends, so an address target is its own piece of work. }
program test_pointer_to_a_dynamic_array;
type
  TDyn = array of LongWord;
  PDyn = ^TDyn;
  PStr = ^AnsiString;
var
  dy, other: TDyn; pd: PDyn;
  s: AnsiString; ps: PStr;
  i: Integer;
begin
  SetLength(dy, 5);
  pd := @dy;

  { the identity that names the bug }
  WriteLn('is handle? ', PtrUInt(pd) = PtrUInt(Pointer(dy)));
  WriteLn('is elem0?  ', PtrUInt(pd) = PtrUInt(@dy[0]));

  { ...and the staleness it caused: the pointer must follow a reallocation }
  WriteLn('len ', Length(pd^));
  SetLength(dy, 9);
  WriteLn('after grow ', Length(pd^));
  SetLength(dy, 3);
  WriteLn('after shrink ', Length(pd^));

  { read and write through the deref reach the SAME array }
  SetLength(dy, 4);
  for i := 0 to High(dy) do dy[i] := (i + 1) * 10;
  Write('read'); for i := 0 to High(pd^) do Write(' ', pd^[i]); WriteLn;
  pd^[1] := 77;
  WriteLn('write ', dy[1]);
  WriteLn('bounds ', Low(pd^), ' ', High(pd^));

  { whole-array assignment through the pointer rebinds the VARIABLE }
  SetLength(other, 2); other[0] := 5; other[1] := 6;
  pd^ := other;
  WriteLn('rebind ', Length(dy), ' ', dy[0], ' ', dy[1]);

  { the managed-string precedent, which this now matches }
  s := 'abc'; ps := @s;
  WriteLn('str is handle? ', PtrUInt(ps) = PtrUInt(Pointer(s)));
  s := 'abcdefgh';
  WriteLn('str after grow ', Length(ps^), ' ', ps^);
end.
