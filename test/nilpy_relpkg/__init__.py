# A package __init__.py that reaches its own siblings by RELATIVE import.
# This is the shape every real Python distribution ships and the one no
# single-file .npy test can express — see the test that imports this.
from .two import A, B
from . import two
from .two import A as RENAMED
# ...and the MODULE-alias spelling. `from . import two` and
# `from .two import A as RENAMED` both worked while this one bound nothing --
# both `from . import` arms consumed the `as <name>` and threw it away, so
# _two read as an undefined variable. See PyBindImportUnitAlias.
from . import two as _two

S = A + B + two.B
T = two.bump(A)
U = RENAMED + 100
V = _two.bump(_two.B)
