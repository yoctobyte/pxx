# try / except ImportError / else, with an IMPORT in the try body.
#
# THE GUARD IS NEVER `ctypes`, AND THAT IS THE FIXTURE RATHER THAN A DETAIL.
# The construct's real use is backend selection, where CPython resolves ctypes
# and pxx does not -- which would have the oracle and the subject running
# DIFFERENT arms, so the differential could not fail at all. Both guards below
# are decided the same way under both runtimes: one module absent everywhere,
# one present everywhere.
#
# BOTH IMPORT SPELLINGS ARE HERE BECAUSE THEY REACH THE ARM SKIP BY DIFFERENT
# DOORS. `from . import mod as impl` binds a UNIT ALIAS -- a compile-time,
# first-wins table, so a dead arm's registration beats the live arm's rebind
# outright. `from .mod import N as impl` binds a SYMBOL, resolved through flat
# unit scope. The first is the spelling lekkerzeilen's platform seam writes; the
# second is what a module re-exporting one name writes. A fix to either layer
# alone leaves the other silent, which is the whole history of this area.
#
# THE TWO ARM MODULES MUST NOT NAME THEIR MEMBERS ALIKE, and the first draft of
# this file did. `from .a import N as X` resolves N through FLAT unit scope, so
# two modules each declaring N collide and the later one answers for both --
# measured with no try/except in the file at all. Naming both `NAME` to sharpen
# the differential is what manufactured it, and it duly reported the handler arm
# returning the else arm's value: a real defect wearing the costume of the bug
# under test. That is
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope, re-ranked
# 45 -> 60 on this measurement. Let the MODULE carry the identity, not the
# member.

# ARM 1: the guarded import MISSES, so the handler runs and the `else` must NOT.
try:
    import definitely_no_such_module_nilpy_tryelse  # noqa: F401
except ImportError:
    from . import absent_arm as miss_impl
    from .absent_arm import ABSENT_WHO as miss_sym
    MISS_WHICH = "handler"
else:
    from . import present_arm as miss_impl
    from .present_arm import PRESENT_WHO as miss_sym
    MISS_WHICH = "else"

# ARM 2: the guarded import RESOLVES, so the `else` runs and the handler must
# NOT -- and the else's own body, including a use of the module the try just
# imported, must be live.
#
# THIS ARM IS THE ONE THAT CATCHES A PARSER-ONLY FIX, and the ordinary no-`else`
# idiom cannot: there the LIVE arm is lexically first in both outcomes and wins
# the first-wins table by position, so a dead arm's binding is invisible. An
# `else:` inverts that -- it puts the live arm AFTER the dead handler.
try:
    import math
except ImportError:
    from . import absent_arm as hit_impl
    from .absent_arm import ABSENT_WHO as hit_sym
    HIT_WHICH = "handler"
    HIT_FLOOR = -1
else:
    from . import present_arm as hit_impl
    from .present_arm import PRESENT_WHO as hit_sym
    HIT_WHICH = "else"
    HIT_FLOOR = math.floor(2.5)


def miss():
    return MISS_WHICH, miss_impl.WHO, miss_sym


def hit():
    return HIT_WHICH, hit_impl.WHO, hit_sym, HIT_FLOOR
