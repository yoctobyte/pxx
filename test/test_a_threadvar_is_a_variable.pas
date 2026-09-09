program test_a_threadvar_is_a_variable;
{ feature-p-threadvar-is-not-supported-at-any-scope -- the SINGLE-THREADED half,
  and it is an fpc differential on purpose.

  A threadvar in a program that never spawns a thread is an ordinary variable
  with one copy, so every row here has an answer fpc agrees with byte for byte
  (measured against FPC 3.2.2, `fpc -Mobjfpc`). That is worth more than a
  pxx-only assertion: it fixes the LANGUAGE surface -- scope, `@`, a var
  parameter, arithmetic, a second name in a group, a non-integer type -- against
  an implementation that has had it for decades, and it does so without needing
  threads, so it runs on any host and in the quick tier.

  THE PER-THREAD CLAIM IS NOT HERE, deliberately, because a single-threaded run
  cannot distinguish a threadvar from a global and a row that cannot fail is not
  a row. test_a_threadvar_is_per_thread.pas is that half; it carries a
  process-wide global as its positive control.

  `threadvar` is not a token in this dialect -- it is an identifier the section
  dispatcher recognises -- so the `var` section above it is also a live test:
  without `threadvar` in that section's stop-word set it would be read as the
  next variable NAME. }

uses sysutils;

var
  before: LongInt;

threadvar
  t: LongInt;
  u: LongInt;      { a second name in the same group }

var
  after: LongInt;  { ...and a `var` section the threadvar section did not eat }

threadvar
  d: Double;
  ptr: Pointer;

procedure Bump(var n: LongInt);
begin
  n := n + 5;
end;

var
  q: PLongInt;

begin
  before := 1;
  after := 2;
  t := 10;
  u := 20;
  WriteLn('t=', t, ' u=', u, ' before=', before, ' after=', after);

  Bump(t);
  WriteLn('after var param t=', t);

  q := @t;
  q^ := q^ * 2;
  WriteLn('through a pointer t=', t, ' q^=', q^);

  Inc(t);
  Dec(t, 3);
  WriteLn('inc/dec t=', t);

  WriteLn('expression=', t * 3 + u);
  if t > u then WriteLn('cmp t>u') else WriteLn('cmp t<=u');

  d := 1.5;
  d := d * 3;
  WriteLn('d=', d:0:4);

  ptr := @before;
  WriteLn('ptr points at before=', ptr = Pointer(@before));

  { the group's two names are INDEPENDENT storage, not one slot reused }
  t := 7; u := 9;
  WriteLn('independent t=', t, ' u=', u);
end.
