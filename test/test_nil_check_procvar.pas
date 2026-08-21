program test_nil_check_procvar;
{ The emitted nil check, WITHOUT sysutils — "FPC-without-sysutils behaviour",
  which is what every member of the PXXDivZero/Overflow/RangeError/IoError hook
  family does when its hook slot is nil: a message and Halt(n).

  A call through a nil procedure variable is the worst-behaved of the nil
  dereferences: it JUMPS TO ADDRESS 0, so there is no faulting instruction
  inside the program, no frame, and a backtrace that names nothing. The check
  fires BEFORE the call, from ordinary call context — which is also what makes
  the sysutils half (test_nil_check_catchable.pas) able to raise past it, where
  a signal handler cannot unwind.

  `before` must print first, so the row also proves the check fired where it was
  supposed to and not earlier. Run with --no-nil-check the same binary dies on
  139 with nothing printed after `before`, and the Makefile asserts that half
  too — the default is the claim, so both directions have to be pinned.
  feature-a-emitted-nil-checks }
type TProc = procedure;
var f: TProc;
begin
  writeln('before');
  f := nil;
  f();
  writeln('after');    { unreachable in both directions }
end.
