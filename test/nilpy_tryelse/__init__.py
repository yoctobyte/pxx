# try / except ImportError / else, with an IMPORT in the try body.
#
# THE GUARD IS NEVER `ctypes`, AND THAT IS THE FIXTURE RATHER THAN A DETAIL.
# The construct's real use is backend selection, where CPython resolves ctypes
# and pxx does not -- which would have the oracle and the subject running
# DIFFERENT arms, so the differential could not fail at all. Both guards below
# are decided the same way under both runtimes: one module absent everywhere,
# one present everywhere.
#
# THE ARMS BIND A UNIT ALIAS (`from . import X as impl`), NOT A SYMBOL
# (`from .X import N as impl`), AND THAT IS LOAD-BEARING. Both spellings are
# the real idiom; only the first is correct today. A dead arm's unit alias is
# rolled back with the block, but a dead arm's imported SYMBOL is resolved by
# PyPreScanImports -- which has no notion of reachability -- and binds at
# module scope, so the value from the arm that did NOT run is visible
# afterwards where CPython raises NameError. That is pre-existing, is not
# specific to `else` (it reproduces with no else in the file at all), and is
# bug-n-an-import-on-a-path-made-dead-by-a-failed-guarded-import-is-still-resolved.
# Writing the symbol spelling here would red this fixture for a defect it is
# not about -- and, worse, would read as a regression in whatever lands beside
# it.

# ARM 1: the guarded import MISSES, so the handler runs and the `else` must NOT.
try:
    import definitely_no_such_module_nilpy_tryelse  # noqa: F401
except ImportError:
    from . import absent_arm as miss_impl
    MISS_WHICH = "handler"
else:
    from . import present_arm as miss_impl
    MISS_WHICH = "else"

# ARM 2: the guarded import RESOLVES, so the `else` runs and the handler must
# NOT -- and the else's own body, including a use of the module the try just
# imported, must be live.
try:
    import math
except ImportError:
    from . import absent_arm as hit_impl
    HIT_WHICH = "handler"
    HIT_FLOOR = -1
else:
    from . import present_arm as hit_impl
    HIT_WHICH = "else"
    HIT_FLOOR = math.floor(2.5)


def miss():
    return MISS_WHICH, miss_impl.WHO


def hit():
    return HIT_WHICH, hit_impl.WHO, HIT_FLOOR
