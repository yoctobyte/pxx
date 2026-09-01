program TestManagedDynArrayFieldLeaks;
{ A DYNAMIC ARRAY OF ANSISTRING held as a FIELD released the array and leaked
  every string in it.

  UFldTk of an array field is its ELEMENT type, and both RTTI descriptor
  writers asked `= tyAnsiString` BEFORE asking `is this a dynamic array`. So
  `v: array of AnsiString` was described as a plain String member; the
  descriptor named the array HANDLE a string, and PXXRecordRelease's kind-1 arm
  ran PXXStrDecRef on it. That decrements the word at the array's refcount
  offset and frees the array BLOCK -- so it looked like it worked, exactly one
  free per record -- while the elements were never walked.

  Measured before the fix, 1500 trips over a record local holding a 1-element
  array: allocs=3000 frees=1499 live=1501. One free per iteration, the array,
  never the string. With 3 elements it leaked 3 per trip: the leak scales with
  the ELEMENT count, which is what identifies the elements rather than the
  array as the survivors. Same on all five runnable backends -- the descriptor
  is shared, so a cross-target differential is blind to this by construction.

  THE ARMS ARE NOT INTERCHANGEABLE. Each one is here because it fails for a
  different reason:

  - dyn/record   the bug itself, in a record local.
  - dyn/class    the same field in a class instance, freed via Free. A second
                 descriptor writer, and it had the identical wrong order -- one
                 was found by grepping for the sibling, not by testing.
  - recelem      `array of TE` where TE is a record holding a string. This arm
                 ALWAYS PASSED, and that is exactly why it is here: tyRecord
                 does not collide with the string test, so it reached the
                 dyn-array arm and got a correct element walk. It is the
                 control that says the walk and the plumbing were fine and only
                 the classification was wrong.
  - fixed        `array[0..2] of AnsiString`. The fix REORDERS the branch that
                 catches this, so this is the arm a careless reorder breaks: a
                 fixed array must still land on the string arm, where arrCount
                 carries its length. It was correct before and must stay so.
  - mixed        all of them in one record, to catch a member-walk that gets
                 the right kinds but the wrong offsets or stride.

  Run with -dPXX_ALLOC_CENSUS; tools/assert_no_leak.sh bounds live objects
  absolutely. }

type
  TE = record s: AnsiString; end;

  TRec = record v: array of AnsiString; end;
  TRecElem = record v: array of TE; end;
  TFixed = record v: array[0..2] of AnsiString; end;
  TMixed = record
    s: AnsiString;
    dyn: array of AnsiString;
    fix: array[0..1] of AnsiString;
    n: Integer;
  end;

  TCls = class
  public
    v: array of AnsiString;
  end;

var
  i, k: Integer;

function Tag(n: Integer): AnsiString;
begin
  Tag := 'tag' + Chr(97 + (n mod 26));
end;

procedure DynInRecord(n: Integer);
var r: TRec; j: Integer;
begin
  SetLength(r.v, 3);
  for j := 0 to 2 do r.v[j] := Tag(n + j);
  if (r.v[0] <> '') and (r.v[2] <> '') then k := k + 1;
end;

procedure RecElems(n: Integer);
var r: TRecElem; j: Integer;
begin
  SetLength(r.v, 3);
  for j := 0 to 2 do r.v[j].s := Tag(n + j);
  if (r.v[0].s <> '') and (r.v[2].s <> '') then k := k + 1;
end;

procedure FixedInRecord(n: Integer);
var r: TFixed; j: Integer;
begin
  for j := 0 to 2 do r.v[j] := Tag(n + j);
  if (r.v[0] <> '') and (r.v[2] <> '') then k := k + 1;
end;

procedure MixedRecord(n: Integer);
var r: TMixed;
begin
  r.s := Tag(n);
  SetLength(r.dyn, 2);
  r.dyn[0] := Tag(n + 1);
  r.dyn[1] := Tag(n + 2);
  r.fix[0] := Tag(n + 3);
  r.fix[1] := Tag(n + 4);
  r.n := n;
  if (r.s <> '') and (r.dyn[1] <> '') and (r.fix[1] <> '') and (r.n = n) then
    k := k + 1;
end;

procedure DynInClass(n: Integer);
var o: TCls; j: Integer;
begin
  o := TCls.Create;
  SetLength(o.v, 3);
  for j := 0 to 2 do o.v[j] := Tag(n + j);
  if o.v[0] <> '' then k := k + 1;
  o.Free;
end;

begin
  k := 0;
  for i := 1 to 1000 do DynInRecord(i);
  Writeln('dynrec ', k);

  k := 0;
  for i := 1 to 1000 do RecElems(i);
  Writeln('recelem ', k);

  k := 0;
  for i := 1 to 1000 do FixedInRecord(i);
  Writeln('fixed ', k);

  k := 0;
  for i := 1 to 1000 do MixedRecord(i);
  Writeln('mixed ', k);

  k := 0;
  for i := 1 to 1000 do DynInClass(i);
  Writeln('dyncls ', k);
end.
