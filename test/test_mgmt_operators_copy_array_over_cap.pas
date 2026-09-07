program test_mgmt_operators_copy_array_over_cap;
{ 200 elements, each wanting one `class operator Copy` call — well over
  REC_COPY_UNROLL_MAX (64), whatever that number is set to next.

  THE CAP IS A CLIFF IN CORRECTNESS, NOT IN SPEED: over it the whole-array
  assignment falls back to the byte copy, which is the defect
  bug-a-a-whole-record-assignment-does-not-run-a-contained-fields-copy-operator
  describes. Nothing in the source says which side of the line an array is on,
  and adding one element moves it. So the emitter WARNS, and this file exists
  for the Makefile to assert that it does.

  ITS OUTPUT IS DELIBERATELY NOT ASSERTED. The output of the over-cap case IS
  the wrong answer; a fixture pinning it would be a regression assertion wearing
  the shape of a control, and it would go red the day someone raises the cap or
  replaces the unroll with a loop. The Makefile greps the warning instead, and
  pairs it with the UNDER-cap fixture, which must not warn. 200 is far enough
  above 64 that raising the cap does not silently disarm this. }
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  TR = record
    id: Integer;
    class operator Copy(constref src: TR; var dst: TR);
  end;
var fired: Integer;

class operator TR.Copy(constref src: TR; var dst: TR);
begin
  fired := fired + 1;
  dst.id := src.id;
end;

procedure P;
var s, d: array[0..199] of TR;
begin
  s[0].id := 5;
  d := s;
  writeln('over-cap fired=', fired, ' d[0].id=', d[0].id);
end;

begin
  fired := 0;
  P;
end.
