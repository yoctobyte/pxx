{ `[e1, ..., en]` as the operand of Low / High / Length is an open-array
  CONSTRUCTOR, not a set, and the answer is a compile-time COUNT whatever the
  elements are.

  pxx read the brackets as a set and then took Length of the BITMASK:

    Length([1])        -> 2      (bit 1)
    Length([1,2])      -> 6      (bits 1 and 2)
    Length([1,2,3])    -> 14
    Length([5,9])      -> 544
    Length(['a','b'])  -> 0      (bits 97 and 98, past the low word)

  and `Low([1,2])` / `High([1,2])` were refused outright with *expected array
  variable or ordinal type*. The Length rows are the expensive half: a small set
  produces a small plausible number, which is how this survived.

  The last block is the neighbouring silent wrong answer, now a refusal:
  `Length(<a set>)` read the 32-byte bitset as a string handle and answered the
  low word of the bitmask. FPC says `Type mismatch`; pxx says a set has no
  length. It is a %fail-shaped assertion so it lives in the Makefile beside
  this, not here.

  Every row below is `fpc -O1 -Mobjfpc` 3.2.2's.
  bug-p-length-low-and-high-of-a-set-answer-the-bitmask }
program test_open_array_constructor_bounds;

type
  TDay  = (dMo, dTu, dWe);
  TDays = set of TDay;

function CountOpen(const a: array of Integer): Integer;
begin CountOpen := Length(a); end;

var
  x, y: Integer;
  ds: array of TDays;      { an array whose ELEMENT is a set — Length is legal }
  d: TDays;
begin
  x := 1; y := 2;

  writeln(Low([]),   '|', High([]),   '|', Length([]));
  writeln(Low([7]),  '|', High([7]),  '|', Length([7]));
  writeln(Low([1,2]),'|', High([1,2]),'|', Length([1,2]));
  writeln(Length([1,2,3]), '|', Length([5,9]), '|', Length([1,2,3,4,5]));
  writeln(Length(['a','b']), '|', Length(['ab','cd','ef']));

  { non-constant elements: still a compile-time count }
  writeln(Length([x,y]), '|', High([x,y]));

  { nested constructors count at the top level only }
  writeln(Length([[1,2],[3,4],[5,6]]));

  { the open-array PARAMETER form, which always worked, beside them }
  writeln(CountOpen([]), '|', CountOpen([1,2,3]));

  { a real set still behaves like a set }
  d := [dMo, dWe];
  writeln((dWe in d), '|', (dTu in d));

  { and an array OF sets still has a length — the exclusion this needed }
  SetLength(ds, 2);
  ds[0] := [dMo]; ds[1] := [dTu, dWe];
  writeln(Length(ds), '|', (dTu in ds[1]));
end.
