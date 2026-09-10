# The portability seam, written the way a real application writes it:
# a guarded import decides which sibling module the name `backend` refers to.
#
# lekkerzeilen/platform/__init__.py is this file with SDL2 in it.
#
# THE GUARDED MODULE IS A NAME NEITHER RUNTIME HAS, so CPython takes the same
# branch pxx does and every row below is a cross-check rather than a record of
# our divergence.
try:
    import definitely_no_such_module_4c71
    from . import primary as backend
    backend_kind = "primary"
except ImportError:
    from . import fallback as backend
    backend_kind = "fallback"

# The mirror: the guarded import RESOLVES, so the try arm is the live one and
# its alias must win. Without this row the fix reads as "the handler always
# wins", which is a different and wrong rule.
try:
    import math
    from . import primary as chosen
    chosen_kind = "primary"
except ImportError:
    from . import fallback as chosen
    chosen_kind = "fallback"
