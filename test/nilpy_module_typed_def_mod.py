# A def in an imported module keeps its annotated types. Compiled both ways by
# the Makefile against one .expected: as the main program, and imported by
# test_nilpy_a_module_def_keeps_its_annotations.npy.
#
# The "is this def used as a VALUE" scan ran over [0, end of this module),
# which in an imported module also held every Pascal unit lexed before it --
# pylib, the RTL -- matched case-insensitively. `flen` met pylib's `FLen:
# Integer`, so flen's param and result became Variants, and Length(line) then
# read the Variant's tag: 6 on x86-64, 0 on i386. The Makefile row also pins
# the candidate count through PXXDBG=n.dval (61081 before, 12 after).
from typing import Callable


def flen(line: str) -> int:
    n = Length(line)
    return n


def fidx(line: str) -> str:
    c = line[1]
    return c


def twice(x: int) -> int:
    return x * 2


def apply(f: Callable[[int], int], v: int) -> int:
    return f(v)


print(flen("ab"), fidx("ab"), apply(twice, 4))
