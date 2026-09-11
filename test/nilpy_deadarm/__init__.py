try:
    import definitely_no_such_module_4c71
    from . import deadctypes as backend
    kind = "deadctypes"
except ImportError:
    from . import light as backend
    kind = "light"

try:
    import definitely_no_such_module_4c71
    from . import deadname as other
    other_kind = "deadname"
except ImportError:
    from . import light as other
    other_kind = "light"

try:
    import math
    from . import heavy as live
    live_kind = "heavy"
except ImportError:
    from . import light as live
    live_kind = "light"

# THE PRESENCE CONTROL FOR THE NARROWING, and without it the fix above is an
# absence asserting itself. `SoftArmDead` had to be told apart from "the module
# is missing", because the latter DOES bind the from-imported name to None so
# that guarded code compiles and fails (or is skipped) at run time. Here the
# guarded import is the FIRST in its arm, so nothing has missed before it and
# the None binding must still happen: the reference to `Image` below has to
# COMPILE. Suppress the binding by mistake and pxx answers `undefined variable
# (Image)` at compile time, where CPython is perfectly happy because the line
# never runs.
try:
    from definitely_no_such_module_4c71 import Image
    have_image = True
except ImportError:
    have_image = False


def image_probe():
    if have_image:
        return Image.new()
    return "absent"
