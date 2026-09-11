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
