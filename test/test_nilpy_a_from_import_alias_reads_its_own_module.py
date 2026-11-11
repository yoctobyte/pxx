# `from M import X as Y` takes X from M, not from whichever unit flat scope
# meets first: two modules exporting one name, and a swap inside one import.
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope
from asrc_m import A as MA
from asrc_n import A as NA
print(MA, NA)
from asrc_m import f as mf
from asrc_n import f as nf
print(mf(), nf())
from asrc_m import A as B, B as A
print(A * 1000 + B)
from asrc_m import h as hh
print(hh())
# a zero-argument def renamed onto a name the source module also defines
from asrc_m import f as g
print(g(), g.__name__)
