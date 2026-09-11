# A package whose ONLY notable property is that it guards an import that MISSES.
# That one construct used to poison its importer: `SoftUnitMissed` is a global,
# it came back out of ParseUsesUnit, and the from-import that pulled this package
# in read the flag as ITS OWN miss and bound KEY_ESCAPE and QUIT to None.
#
# THE GUARDED IMPORT MUST ACTUALLY MISS, AND IT MUST BE A `from ... import`.
# Measured 2026-09-11 on the fix-disabled binary: with `try: import ctypes` here
# instead, this fixture printed the CORRECT values and could not discriminate --
# a guard that cannot fail. Keep the absent module absent and keep the spelling.
#
# ISOLATION IS THE OTHER HALF OF THE FIXTURE. The leak fires only when the
# importer's resolution actually COMPILES this unit; an already-compiled one
# exits early and cannot be poisoned. Rows appended to a fixture that has already
# imported this package are therefore a guard that cannot fail -- measured as
# byte-identical output with the fix disabled. Import this package ONCE.
KEY_ESCAPE = 27
QUIT = "quit"

try:
    from definitely_no_such_module_nilpy_guardpoison import Image
    have = True
except ImportError:
    have = False
