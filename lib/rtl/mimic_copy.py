# SPDX-License-Identifier: 0BSD
"""mimic_copy -- CPython's `copy.copy`, for the container cases.

Reached as `import copy`, which the NilPy import resolver maps to this file and
announces (`note: copy -> mimic_copy (shim, subset)`). Not named `copy.py`: no
file in this tree carries an upstream package name.

WHAT `copy.copy` ACTUALLY IS, AND WHY THIS ONE CANNOT BE COMPLETE. In CPython
`copy.copy` is a dispatcher, not an algorithm. It asks the object how to copy
itself -- `__copy__`, then `__reduce_ex__`, then a class-dependent fallback
that rebuilds an instance and copies its `__dict__`. Every step of that is
introspection NilPy does not offer, so an arbitrary-object `copy` cannot be
written here at all.

What CAN be written exactly is the case the dispatcher handles first and the
case callers overwhelmingly mean: the builtin containers, where a shallow copy
is a fresh container holding the same elements. That is what this provides, and
for anything else it RAISES. A `copy` that returned its argument unchanged for
the objects it could not handle would be the worst possible shim -- every
caller would appear to work while sharing the state it asked to have copied,
and the damage would surface as an unexplained aliasing bug far from here.
See devdocs/dev/python-compat-tiers.md: a shim that states its subset and fails
loudly beats one that approximates.

SCOPE. `html5lib/treebuilders/etree.py` does `from copy import copy` and
applies it to an element's attribute dict. Lists, sets and the immutables are
here because they are the same dispatch and cost a line each.

DELIBERATELY ABSENT: `deepcopy`. It is not a bigger version of this -- it needs
the memo table and the same introspection protocol to recurse through arbitrary
objects, and a "deepcopy" that only went one level down would be a shallow copy
under a name that promises otherwise. A caller who needs it gets a loud
unresolved-name error.
"""


class Error(Exception):
    """CPython names this `copy.Error`; callers occasionally catch it."""


def copy(x):
    """A shallow copy of a builtin container; anything else raises.

    The immutables (str, bytes, int, float, bool, tuple, None) are returned as
    themselves -- which is not a special case but the correct answer, and is
    exactly what CPython does: copying a value nobody can mutate is identity.
    """
    if isinstance(x, dict):
        return dict(x)
    if isinstance(x, list):
        return list(x)
    if isinstance(x, set):
        return set(x)
    if isinstance(x, frozenset):
        return frozenset(x)
    if isinstance(x, (str, bytes, int, float, bool, tuple)):
        return x
    if x is None:
        return x
    raise Error(
        "copy.copy: this shim copies builtin containers only, and got "
        "something else. Copying an arbitrary object needs __copy__ / "
        "__reduce_ex__ introspection that NilPy does not have, and returning "
        "the object unchanged would silently share the state you asked to "
        "copy (lib/rtl/mimic_copy.py)")
