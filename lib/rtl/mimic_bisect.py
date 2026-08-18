# SPDX-License-Identifier: 0BSD
"""mimic_bisect -- CPython's `bisect` module: binary search on a sorted list.

Reached as `import bisect`, which the NilPy import resolver maps to this file
and announces (`note: bisect -> mimic_bisect (shim, subset)`). Not named
`bisect.py`: no file in this tree carries an upstream package name, so the tree
always says what a thing is, and `--no-shims` can refuse the whole category by
the `mimic_` mapping rather than by a list of names.

WHY THIS ONE IS SAFE TO WRITE COMPLETE. `bisect` is an algorithm, not a
platform surface: the six public functions are fully specified by CPython's
docs, they touch nothing outside the list handed to them, and the reference
implementation is the pure-Python `Lib/bisect.py` this mirrors. There is no
version drift to track and no backend to be wrong about -- so unlike a shim
over an OS or XML facility, "complete" here is achievable and verifiable by
comparing return VALUES against CPython, which test/test_nilpy_mimic_bisect.npy
does.

SCOPE. The corpus uses exactly one name: `html5lib/_trie/py.py` does
`from bisect import bisect_left`. The other five are here anyway because they
are the same eight lines twice and a caller reaches for `insort` reflexively --
this is the rare case where guessing beyond the measured scope costs nothing,
because the spec is closed and the implementation is exact.

DELIBERATELY ABSENT: the `key=` parameter (CPython 3.10+). It is a real part of
the modern signature, and adding it means a callable-typed keyword argument
whose absence must be distinguishable from a caller passing None. Nothing in
the corpora uses it; a caller who needs it gets a loud unknown-argument error
rather than a silently ignored key.
"""


def bisect_left(a, x, lo=0, hi=-1):
    """Leftmost index where x can be inserted keeping a sorted.

    hi=-1 means "the end of the list". CPython spells that default None; -1 is
    used here because it keeps the parameter a plain int, and a negative hi is
    not meaningful for this function otherwise.
    """
    if hi < 0:
        hi = len(a)
    while lo < hi:
        mid = (lo + hi) // 2
        if a[mid] < x:
            lo = mid + 1
        else:
            hi = mid
    return lo


def bisect_right(a, x, lo=0, hi=-1):
    """Rightmost index where x can be inserted keeping a sorted."""
    if hi < 0:
        hi = len(a)
    while lo < hi:
        mid = (lo + hi) // 2
        if x < a[mid]:
            hi = mid
        else:
            lo = mid + 1
    return lo


def insort_left(a, x, lo=0, hi=-1):
    """Insert x into sorted a, before any equal entries."""
    a.insert(bisect_left(a, x, lo, hi), x)


def insort_right(a, x, lo=0, hi=-1):
    """Insert x into sorted a, after any equal entries."""
    a.insert(bisect_right(a, x, lo, hi), x)


# CPython's unqualified spellings: both mean the _right variant.
bisect = bisect_right
insort = insort_right
