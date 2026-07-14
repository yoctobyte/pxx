program test_shortstring_trunc;
{ `string[N]` TRUNCATES an oversized source to N — assignment, concatenation,
  record/class field, deref field, managed source — and never writes past the
  slot (the neighbour stays intact).
  bug-pascal-shortstring-no-truncation-buffer-overrun. }
type
  TR = record
    s: string[4];
    guard: Int64;
  end;
  PR = ^TR;
var
  a: string[4];
  b: string[4];
  sh: string[8];
  r: TR;
  p: PR;
  ms: AnsiString;
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
end.
