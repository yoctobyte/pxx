# members of the package's __init__, then a submodule: both readings of
# `from . import`, one statement each
from . import LIMIT, NAME
from . import run as go
from . import sub


def use(x: int) -> int:
    return go(x) + LIMIT + sub.twice(1)


def inner() -> int:
    # the block-level import path is a second copy of the statement parser
    from . import LIMIT as L
    return L + 1


def label() -> str:
    return NAME
