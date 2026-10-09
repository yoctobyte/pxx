# A package that re-exports a CLASS and a function from a subpackage with a
# PARENTHESISED, line-broken from-import -- the TSP shape. Before the fix the
# unit arm of the from-import loop did not take `(`, and an un-aliased class
# re-exported from inside a module registered no alias, so
# `from nilpy_tsppkg import Ephem` named nothing.
from nilpy_tsppkg.parts.ephem import (Ephem,
    epoch)
