program test_shortstring_trunc;
{ `string[N]` TRUNCATES an oversized source to N — assignment, concatenation,
  record/class field, deref field, managed source — and never writes past the
  slot (the neighbour stays intact).
  bug-pascal-shortstring-no-truncation-buffer-overrun.

  Every row below used the INLINE spelling (`a: string[4]`), which is why it
  went on passing while the TYPE-ALIAS spelling (`TS4 = string[4]`) truncated at
  DEFAULT_STR_CAP instead of N — the alias table dropped the capacity. The alias
  rows at the end are that sibling
  (bug-a-string-n-type-alias-loses-its-capacity). }
type
  TR = record
    s: string[4];
    guard: Int64;
  end;
  PR = ^TR;
  TS4 = string[4];              { the ALIAS spelling of the same type }
  TRA = record
    s: TS4;
    guard: Int64;
  end;
var
  a: string[4];
  b: string[4];
  sh: string[8];
  r: TR;
  p: PR;
  ms: AnsiString;
  al: TS4;
  ra: TRA;
begin
  { local assignment truncates; neighbour intact }
  b := 'BBBB';
  a := 'aaaaaaaaaaaaaaaa';
  writeln(a, ' ', Length(a));
  if b = 'BBBB' then writeln('b-ok') else writeln('b-CLOBBERED');

  { plain assignment then concatenation both clamp to 8 }
  sh := 'abcdefghij';
  writeln(sh, ' ', Length(sh));
  sh := sh + 'zz';
  writeln(sh, ' ', Length(sh));

  { record field: literal source }
  r.guard := 12345;
  r.s := 'xxxxxxxxxxxx';
  writeln(r.s, ' ', Length(r.s));
  if r.guard = 12345 then writeln('guard-ok') else writeln('guard-CLOBBERED');

  { record field through a pointer deref }
  New(p);
  p^.guard := 777;
  p^.s := 'yyyyyyyyyyyy';
  writeln(p^.s, ' ', Length(p^.s));
  if p^.guard = 777 then writeln('pguard-ok') else writeln('pguard-CLOBBERED');
  Dispose(p);

  { managed (AnsiString) source into a string[N] field }
  ms := 'zzzzzzzzzzzzzzzz';
  r.guard := 12345;
  r.s := ms;
  writeln(r.s, ' ', Length(r.s));
  if r.guard = 12345 then writeln('mguard-ok') else writeln('mguard-CLOBBERED');

  { the same two shapes declared through a TYPE ALIAS }
  al := 'aaaaaaaaaaaaaaaa';
  writeln(al, ' ', Length(al));
  ra.guard := 999;
  ra.s := 'bbbbbbbbbbbb';
  writeln(ra.s, ' ', Length(ra.s));
  if ra.guard = 999 then writeln('aguard-ok') else writeln('aguard-CLOBBERED');
  al := 'ab';
  al := al + 'cdef';
  writeln(al, ' ', Length(al));
end.
