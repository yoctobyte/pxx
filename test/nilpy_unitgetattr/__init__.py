# THE ALIAS IS CREATED AND USED IN ONE FILE, WHICH IS THE SHAPE THAT MATTERS.
# Re-exporting an alias across a file boundary is a DIFFERENT construct and
# fails on its own account (`no member Cls came of the qualifier backend`) --
# measured 2026-09-11, and it is what a probe written the natural way measures
# instead of this. lekkerzeilen/platform/__init__.py binds and reads the seam in
# one file, so the fixture does too.
from . import backend as backend


class Holder:
    def __init__(self):
        self.present = 99


def g_absent():
    return getattr(backend, "no_such_name", None)


def g_proc():
    # The corpus's own shape, verbatim in structure: probe for a capability,
    # call it if it is there. `opener` has to be a CALLABLE, which is why the
    # declared-proc arm goes through PyMakeFuncValueFor and not through a
    # member read.
    opener = getattr(backend, "present", None)
    return opener(2, 3) if opener else "no opener"


def g_sym():
    return getattr(backend, "CONST", None)


def g_sym_arith():
    # The folded symbol has to be a real value, not a variant that happens to
    # print right: arithmetic on it is the row that would catch that.
    return getattr(backend, "CONST", 0) + 1


def g_dflt():
    return getattr(backend, "nope", 41) + 1


def h_absent():
    return hasattr(backend, "no_such_name")


def h_proc():
    return hasattr(backend, "present")


def h_sym():
    return hasattr(backend, "CONST")


def local_wins():
    # THE CONTROL, and it is chosen so the two answers DIFFER. A local spelled
    # like the module must win -- ConsumeUnitQualifier's rule, and the value
    # door beside this one gates the same way. `present` exists in BOTH the
    # module and the Holder, so a fold that ignored the shadow would return the
    # module's function here instead of 99 and the row would move.
    backend = Holder()
    return getattr(backend, "present", None)
