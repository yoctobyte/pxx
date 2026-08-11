program TestConstArrayOfStringN;
{ Regression for bug-a-a-typed-const-array-of-string-n-is-never-initialised:
  a `const arr: array[..] of string[N] = (...)` initializer stored the source
  string HANDLE into the frozen slot instead of copying the characters, so the
  array read back as pointer garbage with no diagnostic. The initializer flush
  tagged the synthetic target with the DECLARED storage kind (tyFixedString /
  tyShortString) where the resolver gives an ordinary `a[0] := 'aa'` the VALUE
  kind (tyString, via StrValTk) — and IR_STORE_MEM's frozen-string arm only
  fires on tyString, so the store fell through to the generic 8-byte path.

  The routine-LOCAL twin (Loc below) had the identical gap.

  Also covers the capacity clamp on an array element found while fixing it:
  `a[i] := s` with a longer source copied the SOURCE length, overrunning the
  element into its neighbour — the record-field arm of the assign lowering had
  that clamp, the array-element arm did not. FPC truncates; so do we now. }
type
  TS8 = string[8];
const
  F:  array[0..2] of string[8]  = ('dd', 'ee', 'ff');
  Al: array[0..2] of TS8        = ('gg', 'hh', 'ii');
  Sh: array[0..2] of ShortString = ('jj', 'kk', 'll');
  Tr: array[0..1] of string[3]  = ('abcdefg', 'xy');
  ND: array[0..1, 0..1] of string[8] = (('p', 'q'), ('r', 's'));
var
  V: array[0..2] of string[8] = ('v0', 'v1', 'v2');
  A: array[0..1] of string[3];
  s: string;

procedure Loc;
const
  LF: array[0..1] of string[8] = ('m1', 'm2');
begin
  WriteLn('[', LF[0], '][', LF[1], ']');
end;

begin
  WriteLn('[', F[0], '][', F[2], ']');
  WriteLn('[', Al[0], '][', Al[2], ']');
  WriteLn('[', Sh[0], '][', Sh[2], ']');
  WriteLn('[', Tr[0], '][', Tr[1], ']');
  WriteLn('[', ND[0, 0], '][', ND[1, 1], ']');
  WriteLn('[', V[0], '][', V[2], ']');
  WriteLn(Length(F[0]), ' ', Length(Sh[1]), ' ', Length(Tr[0]));
  Loc;
  { the slot is real storage, not a literal alias: overwrite it, and a source
    longer than the capacity truncates instead of running into the neighbour }
  s := 'abcdefg';
  A[0] := s;
  A[1] := 'zz';
  WriteLn('[', A[0], '][', A[1], '] ', Length(A[0]));
end.
