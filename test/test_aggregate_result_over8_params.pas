program test_aggregate_result_over8_params;
{ A function returning an AGGREGATE and taking MORE THAN 8 parameters.

  bug-a-aarch64-cannot-build-programs-with-an-aggregate-result-past-8-params

  aarch64 refused this outright -- `aggregate result with more than 8 params
  not supported` -- so any program reaching it did not build for that target at
  all. It fired from `builtin/pylib.pas`, i.e. for anything pulling that unit
  in, which is how it took `examples/json/jsondemo.pas` out of the aarch64
  corpus without anyone noticing: cross-target sweeps run `test/`, not
  `examples/`, so the aarch64 shard stayed green over a corpus that had quietly
  shrunk. This file is that gap closed -- the shape now lives in `test/`, where
  the sweeps look.

  TWO DEFECTS, AND THE SECOND ONE IS WHY THERE IS A LOOP HERE.

  The visible half was the refusal: AAPCS64 passes the indirect result location
  in x8, and the >8-argument arm loaded x0..x7 from the temp slots but never
  loaded x8, so it raised an Error instead of emitting the call.

  The quiet half was the CLEANUP. The hidden-destination temp is one more
  16-byte slot than the arguments, and the post-call `add sp, sp, #n` did not
  account for it. That does not fault -- it leaks 16 bytes of stack per call and
  returns the right answer, so a single call, or a thousand, looks perfect.

  HENCE THE ITERATION COUNT, WHICH IS SIZED AND NOT GUESSED. At 16 bytes leaked
  per call, exhausting a default 8 MiB stack takes 524288 calls. The first
  version of this test used 200000 and PASSED against a deliberately broken
  compiler -- it was 2.6x too small, and would have shipped as a test that
  cannot fail. 2000000 leaks ~32 MiB, a 4x margin over the limit, and was
  measured to segfault the broken build and pass the fixed one.

  x86-64, i386, arm32 and riscv32 never had either defect -- they already
  lowered this shape -- and all five targets were verified to agree at fix time.
  The Makefile row runs native and aarch64 only: native is the oracle, aarch64
  is the target that was broken, and the other three cost ~13s of qemu per run
  to re-confirm a path this change never touched. }

const
  { > 524288 (8 MiB / 16 bytes per leaked call), with margin -- see above }
  CALLS = 2000000;

type
  TBig = record a, b, c, d: Int64; end;

{ Nine parameters: one past the eight that fit in x0..x7, so the call takes the
  outgoing-stack-block path AND needs the hidden destination register. }
function Make(p1, p2, p3, p4, p5, p6, p7, p8, p9: Int64): TBig;
begin
  Make.a := p1 + p9;
  Make.b := p2 + p8;
  Make.c := p3 + p7;
  Make.d := p4 + p5 + p6;
end;

var
  r: TBig;
  i: Integer;
  s: Int64;
begin
  s := 0;
  for i := 1 to CALLS do
  begin
    { p1 varies so the result cannot be hoisted out of the loop, which would
      turn the stack-leak assertion into a single call wearing a loop. }
    r := Make(i, 2, 3, 4, 5, 6, 7, 8, 9);
    s := s + r.a;
  end;
  { Every field is checked, not just the one the sum reads: the four are
    assembled from different parameter positions, and only p1/p9 and p2/p8
    straddle the register/stack boundary. }
  if (r.a <> CALLS + 9) or (r.b <> 10) or (r.c <> 10) or (r.d <> 15) then
  begin
    writeln('WRONG AGGREGATE ', r.a, ' ', r.b, ' ', r.c, ' ', r.d);
    Halt(1);
  end;
  if s <> (Int64(CALLS) * (Int64(CALLS) + 1)) div 2 + Int64(CALLS) * 9 then
  begin
    writeln('WRONG SUM ', s);
    Halt(1);
  end;
  { A positive token the subject emits itself, rather than a status something
    else could produce. Reaching it at all is the stack-leak assertion. }
  writeln('AGG9 OK calls=', CALLS);
end.
