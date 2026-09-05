{ `Prefetch(const mem)` — an FPC compiler intrinsic that is a CACHE HINT.

  An empty body is a CORRECT implementation, not a stub: a prefetch has no
  observable effect on any program, so a target that does not issue one computes
  the same answers slightly slower. This test asserts exactly that — that the
  call compiles for every lvalue shape FPC's own sources use, and that the
  program's answers are unchanged around it.

  There is no oracle row for "did a cache line move", deliberately: that is not
  observable in Pascal, which is the whole reason the empty body is the
  specification rather than a gap.

  Row `empty string` is the one that matters. FPC's cclasses.pas calls
  `prefetch(AName[1])` where AName may be empty, and that is well-defined there
  because the intrinsic takes the ADDRESS and never reads. The untyped `const`
  parameter is what gives us the same property. }
program test_prefetch_is_a_hint;

type
  TRec = record a, b: Integer; end;
  TArr = array[0..3] of Integer;

var
  s : ShortString;
  e : ShortString;
  r : TRec;
  a : TArr;
  i : Integer;
  p : ^Integer;

begin
  s := 'hello';
  e := '';
  r.a := 11; r.b := 22;
  a[2] := 33;
  i := 44;
  p := @i;

  Prefetch(s[1]);
  Prefetch(e[1]);
  Prefetch(r);
  Prefetch(r.b);
  Prefetch(a[2]);
  Prefetch(i);
  Prefetch(p^);

  writeln('string   : ', s);
  writeln('empty    : [', e, ']');
  writeln('record   : ', r.a, ' ', r.b);
  writeln('array    : ', a[2]);
  writeln('scalar   : ', i);
  writeln('through ^: ', p^);
end.
