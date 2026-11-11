# `super().size()` inside an override of an IMPORTED class's method segfaulted:
# the override's result was inferred as a variant, the join widened the base
# method's result to match, but the base module was already compiled -- so the
# base returned an Int64 that the caller read as a variant pointer. A compiled
# base keeps its type and the override adopts it.
# Also: `from m import Trie` then `class Trie(Trie):` -- the base is m's class,
# not the class being declared ("cannot inherit from itself" before).
# Fixture: test/nilpy_clsfrom26. Expectations are CPython's own output.
from nilpy_clsfrom26._base import Trie
import nilpy_clsfrom26._base as b


class Counted(b.Trie):
    def size(self):
        return super().size() + 10


class Trie(Trie):
    def size(self):
        return super().size() + 100

    def twice(self):
        return self.size() * 2


print(Counted().size(), Trie().size(), Trie().twice(), b.Trie().size())
