# SPDX-License-Identifier: 0BSD
"""mimic_itertools -- CPython's `itertools` module, as plain generators.

Reached as `import itertools` (or `from itertools import chain`), which the
NilPy import resolver maps to this file and announces
(`note: itertools -> mimic_itertools (shim, subset)`). Not named
`itertools.py`: no file in this tree carries an upstream package name.

WHY THIS IS SAFE TO WRITE AS PLAIN PYTHON. Every function here is specified
by a pure-Python "roughly equivalent to" in CPython's own documentation, and
that is what this mirrors, generator for generator. Nothing touches a platform
surface, so the VALUES can be compared against CPython directly, which
test/test_nilpy_mimic_itertools.npy does. A shim in Python is native code here:
the compiler builds it like any other module.

Until this file existed the module was consumed with no backing unit: `import
itertools` was accepted and then every name in it was `undefined variable`,
except `count`, which the frontend special-cased onto pylib's TPyCounter.
`count` is now the generator below like the rest.

THE VARIADIC ONES ARE A PLAIN DEF IN FRONT OF A GENERATOR. NilPy generators
take no `*args`, so `chain(*its)`, `islice(it, *args)`, `zip_longest(*its)` and
`product(*its)` pack their arguments in an ordinary def and hand the tuple to
a private generator. The laziness is unchanged: nothing is drawn from an input
before the consumer asks.

DIVERGENCES, SAID OUT LOUD RATHER THAN HIDDEN:
- `groupby` yields each group as a LIST, not as a sub-iterator that the
  outer iterator invalidates when it advances. `list(g)`, `for x in g`,
  `len(list(g))` agree with CPython; code that relies on a group going empty
  after the outer loop moves on does not.
- `tee` materialises its input once and hands out independent iterators over
  the copy, so it is not lazy (CPython's is). Same values.
- `chain.from_iterable` is spelled `from_iterable` at module level here, since
  a function attribute is not a NilPy construct; `chain.from_iterable(x)` is
  not available.
- `starmap` spreads up to four arguments by position (a call cannot yet
  unpack a sequence into arguments in NilPy).

ABSENT: `batched` (3.12; NilPy's version claim is 3.9).
"""


def count(start=0, step=1):
    n = start
    while True:
        yield n
        n += step


def cycle(iterable):
    saved = []
    for element in iterable:
        yield element
        saved.append(element)
    while len(saved) > 0:
        for element in saved:
            yield element


def repeat(obj, times=None):
    if times is None:
        while True:
            yield obj
    else:
        for i in range(times):
            yield obj


def _accumulate(iterable, func, initial):
    started = False
    total = initial
    if initial is not None:
        started = True
        yield total
    for element in iterable:
        if not started:
            total = element
            started = True
        elif func is None:
            total = total + element
        else:
            total = func(total, element)
        yield total


def accumulate(iterable, func=None, initial=None):
    return _accumulate(iterable, func, initial)


def _chain(iterables):
    for it in iterables:
        for element in it:
            yield element


def chain(*iterables):
    return _chain(iterables)


def from_iterable(iterables):
    return _chain(iterables)


def compress(data, selectors):
    for d, s in zip(data, selectors):
        if s:
            yield d


def dropwhile(predicate, iterable):
    dropping = True
    for x in iterable:
        if dropping and predicate(x):
            continue
        dropping = False
        yield x


def takewhile(predicate, iterable):
    for x in iterable:
        if predicate(x):
            yield x
        else:
            break


def filterfalse(predicate, iterable):
    for x in iterable:
        if predicate is None:
            if not x:
                yield x
        elif not predicate(x):
            yield x


def _groupby(iterable, key):
    have = False
    curkey = None
    group = []
    for element in iterable:
        k = element if key is None else key(element)
        if have and k == curkey:
            group.append(element)
            continue
        if have:
            yield (curkey, group)
        curkey = k
        group = [element]
        have = True
    if have:
        yield (curkey, group)


def groupby(iterable, key=None):
    return _groupby(iterable, key)


def _islice(iterable, start, stop, step):
    i = 0
    nxt = start
    for element in iterable:
        if stop is not None and i >= stop:
            return
        if i == nxt:
            yield element
            nxt += step
        i += 1


def islice(iterable, *args):
    start = 0
    stop = None
    step = 1
    if len(args) == 1:
        stop = args[0]
    elif len(args) == 2:
        start = args[0]
        stop = args[1]
    elif len(args) == 3:
        start = args[0]
        stop = args[1]
        if args[2] is not None:
            step = args[2]
    else:
        raise TypeError("islice expected 2 to 4 arguments")
    if start is None:
        start = 0
    if start < 0 or (stop is not None and stop < 0) or step < 1:
        raise ValueError("Indices for islice() must be None or an integer: 0 <= x <= sys.maxsize.")
    return _islice(iterable, start, stop, step)


def _starmap(function, iterable):
    for args in iterable:
        n = len(args)
        if n == 0:
            yield function()
        elif n == 1:
            yield function(args[0])
        elif n == 2:
            yield function(args[0], args[1])
        elif n == 3:
            yield function(args[0], args[1], args[2])
        else:
            yield function(args[0], args[1], args[2], args[3])


def starmap(function, iterable):
    return _starmap(function, iterable)


def tee(iterable, n=2):
    saved = list(iterable)
    return tuple([iter(saved) for i in range(n)])


def _zip_longest(iterables, fillvalue):
    its = [iter(x) for x in iterables]
    n = len(its)
    while True:
        row = []
        live = 0
        for k in range(n):
            v = next(its[k], _MISSING)
            if v is _MISSING:
                row.append(fillvalue)
            else:
                live += 1
                row.append(v)
        if live == 0:
            return
        yield tuple(row)


class _Missing:
    pass


_MISSING = _Missing()


def zip_longest(*iterables, fillvalue=None):
    return _zip_longest(iterables, fillvalue)


def pairwise(iterable):
    have = False
    prev = None
    for element in iterable:
        if have:
            yield (prev, element)
        prev = element
        have = True


def _product(pools):
    result = [[]]
    for pool in pools:
        result = [x + [y] for x in result for y in pool]
    for prod in result:
        yield tuple(prod)


def product(*iterables, repeat=1):
    pools = []
    for r in range(repeat):
        for it in iterables:
            pools.append(list(it))
    return _product(pools)


def _permutations(pool, r):
    n = len(pool)
    if r > n:
        return
    indices = list(range(n))
    cycles = list(range(n, n - r, -1))
    yield tuple([pool[i] for i in indices[:r]])
    while n > 0:
        found = False
        for i in range(r - 1, -1, -1):
            cycles[i] -= 1
            if cycles[i] == 0:
                indices[i:] = indices[i + 1:] + indices[i:i + 1]
                cycles[i] = n - i
            else:
                j = cycles[i]
                indices[i], indices[-j] = indices[-j], indices[i]
                yield tuple([pool[k] for k in indices[:r]])
                found = True
                break
        if not found:
            return


def permutations(iterable, r=None):
    pool = list(iterable)
    if r is None:
        r = len(pool)
    return _permutations(pool, r)


def _combinations(pool, r):
    n = len(pool)
    if r > n:
        return
    indices = list(range(r))
    yield tuple([pool[i] for i in indices])
    while True:
        found = -1
        for i in range(r - 1, -1, -1):
            if indices[i] != i + n - r:
                found = i
                break
        if found < 0:
            return
        i = found
        indices[i] += 1
        for j in range(i + 1, r):
            indices[j] = indices[j - 1] + 1
        yield tuple([pool[k] for k in indices])


def combinations(iterable, r):
    return _combinations(list(iterable), r)


def _combinations_with_replacement(pool, r):
    n = len(pool)
    if n == 0 and r > 0:
        return
    indices = [0] * r
    yield tuple([pool[i] for i in indices])
    while True:
        found = -1
        for i in range(r - 1, -1, -1):
            if indices[i] != n - 1:
                found = i
                break
        if found < 0:
            return
        i = found
        v = indices[i] + 1
        for j in range(i, r):
            indices[j] = v
        yield tuple([pool[k] for k in indices])


def combinations_with_replacement(iterable, r):
    return _combinations_with_replacement(list(iterable), r)
