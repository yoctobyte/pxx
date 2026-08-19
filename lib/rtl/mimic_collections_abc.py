# SPDX-License-Identifier: 0BSD
"""mimic_collections_abc -- the `Mapping` and `MutableMapping` ABCs, as ordinary
classes.

Reached as `from collections.abc import Mapping` (or `import collections.abc as
cabc`), which the NilPy import resolver maps to this file (dotted module name ->
`mimic_collections_abc`) and announces as a shim. Not named for the upstream
package: no file in this tree carries an upstream name.

WHAT AN ABC IS FOR, AND WHY THAT IS THE WHOLE DESIGN HERE. `Mapping` is not a
container. It stores nothing and it is never instantiated. Its entire value is a
set of MIXIN METHODS -- `get`, `__contains__`, `keys`, `items`, `values` --
derived from the three things a subclass must supply: `__getitem__`, `__len__`
and `__iter__`. So a subclass writes three methods and inherits five, and every
one of the five must dispatch back down into the subclass to work at all. That
downward dispatch is the only thing this file does, and it is where all three of
the compiler workarounds below live.

WHAT IS HERE. `Mapping` and `MutableMapping`, measured against the corpus rather
than copied from the module index:

    html5lib/_utils.py:76               class BoundMethodDispatcher(Mapping)
    html5lib/_trie/_base.py:9           class Trie(Mapping)
    html5lib/treebuilders/dom.py:20     class AttrList(MutableMapping)
    html5lib/treebuilders/etree_lxml.py:198  class Attributes(MutableMapping)

DELIBERATELY ABSENT: `MutableSet`, and every other name in `collections.abc`.
The ticket asked for `MutableSet` "if the corpus asks (check -- do not add
speculatively)"; a grep of html5lib, reportlab, tinycss2 and webencodings for
every `collections` import finds `Mapping`, `MutableMapping`, `OrderedDict`,
`deque` and `namedtuple` and NOTHING else, so it is omitted and a caller gets an
unresolved name at its own use site. Same omit-over-refuse call as
mimic_xml_etree_elementtree, and made the same way -- by grepping, not by
guessing.

ALSO ABSENT: `__eq__` / `__ne__`. CPython's `Mapping` provides them (comparing
`dict(self) == dict(other)`), nothing in the corpora compares two mappings, and
their absence here is NOT silent: a NilPy class without `__eq__` compares by
identity, so `m1 == m2` answers False for equal mappings rather than raising.
That is the one omission on this page that could be quietly wrong, which is why
it is named here rather than merely left out. Add them the day something
compares mappings, with a differential.

THREE COMPILER WORKAROUNDS, all in the downward dispatch, all registered in
devdocs/dev/track-b-workarounds.md with a revert-when-fixed lifecycle:

  1. `__iter__`, `__getitem__` and `__len__` are DECLARED here even though they
     are abstract, because `for k in self` inside a mixin is refused at compile
     time when the class itself declares neither `__iter__` nor
     `__getitem__`+`__len__`
     ([[bug-n-a-mixin-cannot-iterate-self-and-an-abstract-iter-breaks-its-overrides]]).
  2. Each of the three RAISES and then, unreachably, RETURNS. The bare `raise`
     spelling -- the natural one, and CPython's -- makes every subclass's
     `__iter__` override fail at run time with `iter() returned non-iterator of
     type 'Sub'`. Same ticket. The dead `return` is load-bearing; do not tidy it
     away.
  3. The mixins call `self.__getitem__(key)` where `self[key]` is the natural
     spelling, because a subscript written inside a BASE class binds to that
     class's own `__getitem__` instead of dispatching to the subclass override
     ([[bug-n-a-subscript-inside-a-base-class-skips-the-subclass-override]]).
     This one is the dangerous shape: it produced no error, just the base's
     `raise KeyError`, and a base whose stub returned a plausible value instead
     would have answered wrongly in silence.

Nothing in the corpus can reach this file yet. `from collections.abc import
Mapping` never gets here: `PyImportRootIsConsumedOnly` in
`compiler/pyparser.inc:33003` tests only the ROOT of a dotted from-import, and
`collections` is on its consume-and-ignore list, so the whole import is
swallowed and `Mapping` binds to nothing. Filed as
[[bug-n-from-collections-abc-import-is-swallowed-by-the-collections-root-rule]].
The qualified spelling (`import collections.abc as cabc`) does reach here and is
what the test uses.
"""


class Mapping:
    """The read-only mapping ABC: supply `__getitem__`, `__len__` and
    `__iter__`, inherit `get`, `__contains__`, `keys`, `items` and `values`."""

    def __iter__(self):
        # Declared-and-raising rather than absent, and the dead `return` after
        # the raise is required. See workarounds 1 and 2 in the module docstring.
        raise NotImplementedError('Mapping.__iter__ is abstract')
        return iter([])

    def __getitem__(self, key):
        raise KeyError(key)
        return None

    def __len__(self):
        raise NotImplementedError('Mapping.__len__ is abstract')
        return 0

    def get(self, key, default=None):
        """The value for `key`, or `default` -- never a KeyError. This is the
        method that makes a Mapping usable without a try/except, and it is the
        one html5lib's BoundMethodDispatcher overrides."""
        if key in self:
            return self.__getitem__(key)
        return default

    def __contains__(self, key):
        # CPython tries `self[key]` and catches KeyError. Scanning the keys
        # instead is O(n) where upstream is O(1) for a dict-backed subclass, but
        # it asks the subclass only for what a Mapping is required to provide,
        # and it cannot be fooled by a subclass whose __getitem__ raises
        # something other than KeyError.
        for k in self:
            if k == key:
                return True
        return False

    def keys(self):
        """CPython returns a KeysView -- a live, set-like object. This returns a
        list, which is a real divergence and a deliberate one: a view needs
        `__and__`/`__or__`/`__sub__` and a live tie to the mapping, nothing in
        the corpora uses either, and a half-view that looked live and was not
        would be worse than a list that obviously is not one."""
        out = []
        for k in self:
            out.append(k)
        return out

    def items(self):
        out = []
        for k in self:
            out.append((k, self.__getitem__(k)))
        return out

    def values(self):
        out = []
        for k in self:
            out.append(self.__getitem__(k))
        return out


class MutableMapping(Mapping):
    """Adds the write half: supply `__setitem__` and `__delitem__` as well, and
    inherit `pop`, `popitem`, `clear`, `update` and `setdefault` on top of
    everything Mapping gives."""

    def __setitem__(self, key, value):
        raise NotImplementedError('MutableMapping.__setitem__ is abstract')
        return None

    def __delitem__(self, key):
        raise NotImplementedError('MutableMapping.__delitem__ is abstract')
        return None

    def pop(self, key, *args):
        """Remove and return `key`'s value; with a second argument, return that
        instead of raising when the key is absent. Upstream distinguishes "no
        default given" from "default is None" -- `pop(k)` on a missing key
        raises, `pop(k, None)` returns None -- so the two cannot be collapsed
        into `default=None`."""
        if key in self:
            value = self.__getitem__(key)
            self.__delitem__(key)
            return value
        if len(args) > 0:
            return args[0]
        raise KeyError(key)

    def popitem(self):
        """Remove and return SOME (key, value) pair. Upstream makes no ordering
        promise for the ABC, and neither does this."""
        for k in self:
            value = self.__getitem__(k)
            self.__delitem__(k)
            return (k, value)
        raise KeyError('popitem(): mapping is empty')

    def clear(self):
        # Not `for k in self: del self[k]` -- mutating while iterating is
        # undefined here exactly as it is upstream, which is why CPython spells
        # this as a popitem loop too.
        while True:
            try:
                self.popitem()
            except KeyError:
                return

    def update(self, other=None, **kwargs):
        """Accepts a mapping, an iterable of pairs, or keyword arguments, in
        that order of preference -- the same three shapes `dict.update` takes.

        The key-or-pairs test is `isinstance(other, dict) or isinstance(other,
        Mapping)`, where CPython leads with `isinstance(other, Mapping)` (a dict
        is a registered Mapping there) and falls back to `hasattr(other,
        "keys")`. Both halves of that are unavailable: NilPy has no ABC
        registration, so a plain dict is not an instance of this class, and
        `hasattr(a_dict, "keys")` answers **False**
        ([[bug-n-hasattr-through-an-untyped-parameter-is-always-false]], where
        `other` has no static type and so every hasattr answers False) --
        which is not a graceful miss but a crash, because a dict then takes the
        pairs branch, iteration yields its KEYS, and `pair[0]` indexes a
        one-character string. The two isinstance checks cover every shape the
        corpora pass. An arbitrary duck-typed object with a `keys()` method and
        no relation to either type still lands in the pairs branch; that is the
        residue of the hasattr bug and it is named here rather than papered
        over."""
        if other is not None:
            if isinstance(other, dict) or isinstance(other, Mapping):
                for k in other:
                    self.__setitem__(k, other[k])
            else:
                for pair in other:
                    self.__setitem__(pair[0], pair[1])
        for k in kwargs:
            self.__setitem__(k, kwargs[k])

    def setdefault(self, key, default=None):
        if key in self:
            return self.__getitem__(key)
        self.__setitem__(key, default)
        return default
