# A class bound by an un-aliased from-import in the main program is THAT
# module's class, even when another imported module declares a class of the
# same name -- here the base the re-exported class subclasses. Bare `Trie()`
# constructed the BASE (flat scope ranked by uses-order). Fixture:
# test/nilpy_clsfrom26 (a package re-exporting a subclass of _base.Trie).
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope
# Expectations are CPython's own output.
from nilpy_clsfrom26 import Trie
import nilpy_clsfrom26._base as b
x = Trie()
print(x.size(), b.Trie().size(), type(x).__name__, isinstance(x, b.Trie))
