# `from ._base import Trie as ABCTrie` then `class Trie(ABCTrie)` -- html5lib's
# _trie/py.py. The alias resolved by a flat lookup to the importing module's
# OWN Trie, the class became its own parent, and the compile never terminated.
# The Makefile row bounds the compile with `timeout`: a hang has no expected
# output to diff against.  bug-n-compiling-html5lib-trie-never-terminates
# Only the package is imported here: a second, bare import of _base's Trie
# into this module would be the separate same-name collision residue of
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope.
from nilpy_samename26 import Trie, is_base, base_size

t = Trie()
print(t.size(), t.kind())
print(is_base(t), base_size())
