# SPDX-License-Identifier: 0BSD
"""mimic_functools -- the parts of CPython's `functools` a program reaches.

Reached as `import functools` / `from functools import ...`, which the NilPy
import resolver maps to this file (`mimic_` naming, see mimic_bisect.py).
Plain Python on purpose: every piece is a small object or a closure, and the
compiled form of that is native code.

PROVIDED
  reduce(f, iterable[, initial])   CPython's TypeError on an empty iterable
  partial(func, *args, **kw)       a callable object; call-time keywords win
  wraps / update_wrapper           IDENTITY -- they copy __name__/__doc__,
                                   which nothing here reads, so the wrapper is
                                   returned unchanged
  lru_cache(maxsize=128) / cache   `@lru_cache`, `@lru_cache()`,
                                   `@lru_cache(maxsize=N|None)`; cache_info()
                                   and cache_clear(); LRU order is the dict's
                                   insertion order (a hit is moved to the end)
  cmp_to_key(cmp)                  a key object with the six comparisons

DELIBERATELY ABSENT
  total_ordering, singledispatch -- a CLASS decorator and a registry keyed on
  annotations; NilPy refuses a decorated class, so neither could be used.
  lru_cache(typed=True) is accepted and ignored. A cache key is the POSITIONAL
  argument tuple: a cached function called with keywords is not supported.

WHAT IT RESTS ON (2026-10-03): `obj(...)` taking the method argument list
(`__call__(self, *args)`), a callable instance in a key= slot, `*args` and
`**kw` together through a callable value, and a `*args` `__call__` reached
through a variant. Each of those was a crash or a compile error before; the
tests named in that commit pin them, and test/lib_mimic_functools.npy pins
this file against CPython.
"""


def reduce(function, iterable, *initial):
    it = iter(iterable)
    if len(initial) > 0:
        value = initial[0]
    else:
        try:
            value = next(it)
        except StopIteration:
            raise TypeError("reduce() of empty iterable with no initial value")
    for element in it:
        value = function(value, element)
    return value


class partial:
    def __init__(self, func, *args, **keywords):
        self.func = func
        self.args: tuple = args
        self.keywords: dict = keywords

    def __call__(self, *args, **keywords):
        kw = dict(self.keywords)
        kw.update(keywords)
        return self.func(*self.args, *args, **kw)


def update_wrapper(wrapper, wrapped, *rest, **kw):
    return wrapper


def wraps(wrapped, *rest, **kw):
    def deco(wrapper):
        return wrapper
    return deco


class _CacheInfo:
    def __init__(self, hits, misses, maxsize, currsize):
        self.hits = hits
        self.misses = misses
        self.maxsize = maxsize
        self.currsize = currsize

    def __repr__(self):
        return ("CacheInfo(hits=" + str(self.hits) + ", misses=" + str(self.misses)
                + ", maxsize=" + str(self.maxsize) + ", currsize="
                + str(self.currsize) + ")")


class _LruCache:
    def __init__(self, func, maxsize):
        self.func = func
        self.maxsize = maxsize
        self.cache = {}
        self.hits = 0
        self.misses = 0

    def __call__(self, *args):
        key = args
        if key in self.cache:
            self.hits += 1
            value = self.cache[key]
            if self.maxsize is not None:
                del self.cache[key]
                self.cache[key] = value
            return value
        self.misses += 1
        value = self.func(*args)
        if self.maxsize is not None and self.maxsize <= 0:
            return value
        self.cache[key] = value
        if self.maxsize is not None and len(self.cache) > self.maxsize:
            del self.cache[next(iter(self.cache))]
        return value

    def cache_info(self):
        return _CacheInfo(self.hits, self.misses, self.maxsize, len(self.cache))

    def cache_clear(self):
        self.cache = {}
        self.hits = 0
        self.misses = 0


def cache(func):
    return _LruCache(func, None)


def lru_cache(maxsize: object = 128, typed=False):
    if callable(maxsize):
        return _LruCache(maxsize, 128)

    def deco(func):
        return _LruCache(func, maxsize)
    return deco


class _CmpKey:
    def __init__(self, cmp, obj):
        self.cmp = cmp
        self.obj = obj

    def __lt__(self, other):
        return self.cmp(self.obj, other.obj) < 0

    def __gt__(self, other):
        return self.cmp(self.obj, other.obj) > 0

    def __eq__(self, other):
        return self.cmp(self.obj, other.obj) == 0

    def __le__(self, other):
        return self.cmp(self.obj, other.obj) <= 0

    def __ge__(self, other):
        return self.cmp(self.obj, other.obj) >= 0


class _CmpToKey:
    def __init__(self, cmp):
        self.cmp = cmp

    def __call__(self, obj):
        return _CmpKey(self.cmp, obj)


def cmp_to_key(mycmp):
    return _CmpToKey(mycmp)
