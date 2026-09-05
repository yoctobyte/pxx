{ An ARRAY argument must not bind a SCALAR parameter through a METHOD call,
  exactly as it already could not through a free call.

  The free path fills five argument-match side channels before matching;
  MatchArgArray is the one that says "this argument is definitely an array",
  and MatchArgRecMismatch refuses it against a non-array, non-pointer
  parameter. The speculative method-overload probe in FindUMethOverloadAhead
  could not see those channels, so the same call through a method compiled and
  passed the array's ADDRESS as an integer:

    d.One(ia)   ->  one 4306992        (pxx, before)
    One(ia)     ->  refused            (pxx free path, same tree)

  Silent wrong value, no diagnostic, and which spelling you used decided it.
  Measured on pin v403 too, so it is not a regression -- it is the gap.
  refactor-p-the-overload-probe-cannot-see-the-argument-match-channels,
  bug-p-an-array-argument-binds-a-scalar-overload (method spelling).

  fpc 3.2.2 refuses it:
    Incompatible type for arg no. 1: Got "TIA", expected "LongInt"

  This file must NOT compile. The positive half -- the array-shaped arguments
  that must still be ACCEPTED through a method -- is
  test_method_array_arg_ok.pas beside it. }
{$mode objfpc}
program marrfail;
type
  TIA = array[0..2] of Integer;
  TD = class
    procedure One(v: Integer);
  end;
procedure TD.One(v: Integer); begin WriteLn('one ', v); end;
var d: TD; ia: TIA;
begin
  d := TD.Create;
  ia[0] := 11; ia[1] := 22; ia[2] := 33;
  d.One(ia);
end.
