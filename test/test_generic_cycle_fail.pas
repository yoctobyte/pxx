{ Two specializations that require EACH OTHER used to hang the compiler: 100%
  CPU, growing memory, no diagnostic, no end.

  `TP<A,B>` has a member typed `TP<B,A>`, so specializing TP<Integer,string>
  needs TP<string,Integer>, which needs TP<Integer,string> back. A
  specialization with an unregistered prerequisite re-emits itself behind that
  prerequisite and re-parses -- which terminates only while the unmet set
  shrinks, and a cycle shrinks nothing. Each round inserted a fresh copy of
  both declarations into the token stream.

  Must now FAIL with `circular generic specialization`, naming both sides.
  FPC rejects this program too (with a syntax error at the return type), so
  nothing legal is lost; the point is that a compiler must not spin.
  bug-p-mutually-recursive-generic-specialization-hangs-the-compiler }
program test_generic_cycle_fail;
{$mode objfpc}{$H+}{$modeswitch advancedrecords}
type
  generic TP<A, B> = record
    l: A; r: B;
    function Swap: specialize TP<B, A>;
  end;
function TP.Swap: specialize TP<B, A>;
begin Result.l := r; Result.r := l; end;
type TIP = specialize TP<Integer, string>;
var p: TIP;
begin
  p.l := 3; p.r := 'three';
  writeln(p.Swap.r);
end.
