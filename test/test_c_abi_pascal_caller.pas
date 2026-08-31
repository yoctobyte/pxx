program test_c_abi_pascal_caller;
{ A Pascal caller reaching bodied C functions: the shape that distinguishes a
  C frontend which uses the C ABI from one which uses pxx's internal positional
  convention.

  Green on x86-64 and riscv32; RED on aarch64, arm32 and i386, each in its own
  way, which is the whole value of the file -- the three failures have three
  different mechanisms and no single shape finds all of them:

    aarch64  the float bank -- DblFirst, TwoDbl and Flt are wrong because a
             double belongs in d0..d7 and the positional prologue reads x0..x7
    arm32    the even-register pair -- IntFirst alone is wrong, because AAPCS32
             puts a 64-bit argument in an EVEN core-register pair (r2,r3) and
             the word-based convention uses (r1,r2)
    i386     argument ORDER -- ThreeInts gives 321 for 123, visible with no
             float at all

  A pure C program cannot substitute for this: it is self-consistent both before
  and after a convention change (positional on both sides, or C-ABI on both), so
  test-c-conformance-* and test-lua-cross can catch a REGRESSION here but can
  never go red-to-green. test/c_abi_pure_c_control.c is that regression half,
  and the two belong together.

  `mix4` and `eight` USED to be absent here, refused on arm32 as an argument
  block over four core registers, and a compile-time refusal takes the other
  shapes down with it on that target. That refusal is gone
  (bug-a-arm32-cdecl-has-no-aapcs-stack-argument-area), and the two shapes are
  the only ones in this family that reach a stack argument at all -- so until
  2026-08-31 the part of the ABI with no implementation was also the part with
  no test.
  bug-c-a-c-function-s-calling-convention-depends-on-the-target }
uses unit_cabi_bridge;
begin
  Writeln('dbl_first ',  DblFirst(2.5, 4):0:2);
  Writeln('int_first ',  IntFirst(4, 2.5):0:2);
  Writeln('three_ints ', ThreeInts(1, 2, 3));
  Writeln('two_dbl ',    TwoDbl(1.5, 2.5):0:2);
  Writeln('flt ',        Flt(2.5, 4):0:2);
  Writeln('mix4 ',       Mix4(1, 2.0, 3, 4.0):0:2);
  Writeln('eight ',      Eight(1, 2, 3, 4, 5, 6, 7, 8));
  Writeln('pairsum ',    PairSum(1.5, 2.5):0:2);
end.
