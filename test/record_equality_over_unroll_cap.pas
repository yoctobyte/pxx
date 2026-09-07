{ A record whose field-wise expansion would exceed REC_CMP_UNROLL_MAX, so the
  comparison falls back to the pre-2026-09-07 one-word compare AND THE COMPILER
  SAYS SO.

  The warning is the subject here, not the value. Above the cap `a = b` is
  wrong for records differing past the first word, and nothing in the source
  says which side of the cap a record is on -- adding one element to an
  unrelated member moves it. A silent boundary in CORRECTNESS is worse than
  either answer, so the site is required to announce it.

  101 leaves: one Integer plus array[0..99]. The `101 element comparisons`
  text in the recipe's grep is deliberate -- a bare "warning" match would pass
  if some unrelated warning fired and this one stopped.
  bug-a-record-equality-still-compares-one-word-when-a-member-is-an-array }
program record_equality_over_unroll_cap;
type TBig = record n: Integer; v: array[0..99] of Integer; end;
var a, b: TBig; i: Integer;
begin
  for i := 0 to 99 do begin a.v[i] := i; b.v[i] := i; end;
  a.n := 1; b.n := 1;
  b.v[99] := 999;
  if a = b then WriteLn('OVERCAP compared equal') else WriteLn('OVERCAP compared unequal');
end.
