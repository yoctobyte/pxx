# the base is imported under an alias, and the subclass reuses its NAME
from ._base import Trie as ABCTrie


class Trie(ABCTrie):
    def size(self):
        return 2


def is_base(x):
    return isinstance(x, ABCTrie)


def base_size():
    return ABCTrie().size()
