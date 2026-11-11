# Three package-import gaps, one fixture (test/nilpy_pkginit26):
# - `import pkg.mod` runs pkg/__init__ first and binds `pkg`, so `pkg.TOP`
#   reads the package's own name. It was "undefined variable (pkg)", and the
#   package body never ran.  bug-nilpy-importing-a-submodule-skips-the-package-init
# - `from .inner.leaf import val` (relative, dotted) resolves inner/leaf.py; it
#   was "no unit named inner_leaf".
# - `from pkg.inner import leaf` after the package's own `from .leaf import val`
#   binds the module; the alias table looped back on itself and `leaf.val`
#   was "no member val came of the qualifier leaf".
# Only the package __init__ prints: pxx runs a module's imports before its own
# body, so prints in the submodules would come out in a different order (see
# nilpy-semantics-divergences.md).
import nilpy_pkginit26.mod
from nilpy_pkginit26.inner import leaf

print(nilpy_pkginit26.TOP)
print(nilpy_pkginit26.mod.go())
print(leaf.val())
