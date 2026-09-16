program test_var_array_of_sets;
{ A `var` array whose ELEMENTS are sets -- the VAR twin of
  test_const_array_of_sets, and the arm that was still broken after the const
  one was fixed.

  FPC's own compiler/x86_64/cpuinfo.pas is the real-world case:

    cpu_capabilities : array[tcputype] of set of tcpuflags = (
      { cpu_none } [], { Athlon64 } cpu_x86_64_v1_flags, ... );

  -- a VAR, enum-indexed, opening with the empty set. It was one of the two
  errors reported by 132 of FPC's 207 compiler units.

  SAME MECHANISM AS THE CONST TWIN, AND THAT IS THE POINT OF HAVING BOTH.
  ParseVarSection's array-element loop fell through to an ordinal fallback that
  cannot evaluate a `[` and does not CONSUME it either, so the loop spun on one
  token while the element counter advanced once per spin, until the length check
  tripped: `too many array initializer elements`, reported with the position
  still on the FIRST element. A size complaint about a correct size --
  `array[0..5]` with one element failed identically, so the number in the
  message never described the defect. ParseConstSection's loop had already been
  routed through the shared TryParseInitValForm helper for exactly this; the var
  loop was simply never wired to it.

  THE ROWS COVER THE BOUNDARY, NOT ONE EXAMPLE, and each one reaches something
  the others do not:
    - `[]` FIRST, because the empty set is the shape that spins first and an
      empty aggregate is also a value that collides with "nothing was stored".
      Code() returning 0 for it is therefore NOT sufficient on its own -- it is
      only meaningful beside a neighbour in the same array that returns nonzero.
    - an INTEGER-bounded and an ENUM-bounded array, because cpuinfo's is enum
      bounded and the bound is computed on a different path.
    - a routine-LOCAL var array, which goes through LocalInit rather than
      PendingInit -- a different emitter, and where a second encoding would
      drift.
    - a STORE after initialisation. This is the row a const array cannot have,
      and it is the one that proves the elements are real storage rather than a
      baked blob the reader happens to be pointed at.

  Code() returns a BIT COMBINATION rather than a membership flag so a wrong
  32-byte mask cannot look correct by matching on a single probe bit. }
type
  TF = (fa, fb, fc, fd);
  TFSet = set of TF;

function Code(const s: TFSet): Integer;
{ 1 = holds fa, 2 = holds fb, 4 = holds fd. Three independent bits. }
begin
  Result := 0;
  if fa in s then Result := Result + 1;
  if fb in s then Result := Result + 2;
  if fd in s then Result := Result + 4;
end;

var
  { integer-bounded, empty set first }
  tbl: array[0..3] of TFSet = ([], [fa], [fa, fb], [fa, fb, fc, fd]);
  { enum-bounded -- cpuinfo's actual shape }
  cap: array[TF] of TFSet = ([], [fb], [fa, fd], [fd]);

procedure Local;
var
  loc: array[0..2] of TFSet = ([], [fb, fd], [fa]);
  i: Integer;
begin
  for i := 0 to 2 do WriteLn('loc', i, ' ', Code(loc[i]));
end;

var i: Integer; e: TF;
begin
  for i := 0 to 3 do WriteLn('tbl', i, ' ', Code(tbl[i]));
  for e := fa to fd do WriteLn('cap', Ord(e), ' ', Code(cap[e]));
  Local;
  { IT IS A VAR: the elements must be writable storage, not a baked constant.
    Assigning INTO the slot that was initialised empty is the strongest of the
    four, because a reader pointed at a shared read-only blob would either fault
    or corrupt its neighbours -- so tbl1 is re-read afterwards as the witness. }
  tbl[0] := [fa, fd];
  WriteLn('set0 ', Code(tbl[0]));
  WriteLn('keep1 ', Code(tbl[1]));
end.
