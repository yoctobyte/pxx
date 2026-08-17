# A package __init__.py that reaches its own siblings by RELATIVE import.
# This is the shape every real Python distribution ships and the one no
# single-file .npy test can express — see the test that imports this.
from .two import A, B
from . import two
from .two import A as RENAMED

S = A + B + two.B
T = two.bump(A)
U = RENAMED + 100
