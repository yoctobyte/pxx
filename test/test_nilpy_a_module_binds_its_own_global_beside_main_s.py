# A name is bound PER MODULE. Two shapes that read the wrong module's value:
#  - an un-aliased `from am_m import C` beside a later `from am_n import C as NC`:
#    the bare `C` read am_n's (the newest same-named global), CPython am_m's;
#  - a main-program `A` bound before am_n was parsed (the alias swap makes one)
#    took am_n's own top-level `A = 7`, so am_n had no A and NA read main's 18.
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope (residue 1)
from am_m import A as B, B as A
from am_n import A as NA
import am_n
print(A, B, NA, am_n.A, am_n.getA())
from am_m import C
from am_n import C as NC
print(C, NC)
A = 40
print(A, NA, am_n.getA())
