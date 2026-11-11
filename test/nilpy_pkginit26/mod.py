# a RELATIVE import whose module part is itself dotted
from .inner import X
from .inner.leaf import val


def go():
    return X + val()
