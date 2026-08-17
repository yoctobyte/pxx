# SPDX-License-Identifier: 0BSD
"""mimic_six -- the `six` Python-2/3 compatibility surface, for a Python-3-only
dialect.

Reached as `import six`, which the NilPy import resolver maps to this file and
announces (`note: six -> mimic_six (shim, subset)`). The file is NOT named
`six.py` on purpose: no file in this tree carries an upstream package name, so
the tree always says what a thing is, and `--no-shims` can refuse the whole
category by the `mimic_` mapping rather than by a list of names.

WHY THIS IS MOSTLY ONE-LINERS. `six` exists to paper over the Python 2/3 split.
On a Python-3-only dialect almost every name in it is trivially the Python 3
answer -- `text_type` IS `str`, `PY3` IS True -- so this is not an emulation
with behaviour to get wrong, it is a table of aliases. The two exceptions are
called out below and are the only places judgement was needed.

SCOPE IS MEASURED, NOT GUESSED. The names here are what webencodings, html5lib
and tinycss2 actually import, read off the sources with grep, plus the handful
of one-line siblings a `six` user reaches for reflexively. Everything else six
offers is deliberately absent: a shim that states its subset and fails loudly
beats one that approximates (see devdocs/dev/python-compat-tiers.md, T1).

DELIBERATELY ABSENT: `six.moves`. Three corpus sites want `http_client`,
`urllib` and `urllib_parse` from it. Those are stdlib re-exports, so they need
`urllib` and `http.client` to exist at all -- a different job with a different
blocker, not something this file can fake.
"""

PY2 = False
PY3 = True

# The type aliases. On Python 3 these are just the builtins, and holding a type
# in a module-level name works: `isinstance(s, string_types)` and `text_type(x)`
# both answer correctly.
text_type = str
binary_type = bytes
string_types = (str,)
integer_types = (int,)
class_types = (type,)
MAXSIZE = 9223372036854775807


def unichr(i):
    """Python 2's `unichr`, which is Python 3's `chr`.

    A `def` rather than `unichr = chr`: a builtin FUNCTION is not currently
    bindable to a name here the way a builtin TYPE is, and wrapping costs one
    call while the alias costs a compile error. html5lib imports this as
    `from six import unichr as chr`, so the name it lands under is the caller's
    business either way.
    """
    return chr(i)


def iterkeys(d):
    return d.keys()


def itervalues(d):
    return d.values()


def iteritems(d):
    return d.items()


def viewkeys(d):
    """`six.viewkeys(d)` -- Python 2's `d.viewkeys()`, i.e. Python 3's `d.keys()`.

    Returns a SET rather than a keys view, and that is the one deliberate
    deviation in this file. The only corpus use is set algebra --
    `viewkeys(token['data']) & viewkeys(replacements)` in html5lib's
    html5parser -- and `&` between two `.keys()` results is not supported here
    (they come back as lists, and `list & list` is a TypeError) while `&`
    between two sets works. Measured both ways before choosing.

    What this gives up is liveness: a real view tracks later mutations of `d`,
    this is a snapshot. No corpus site holds one across a mutation, and the
    alternative -- returning the unsupported thing so the caller fails at `&` --
    would be faithful and useless.

    NOTE it is a FUNCTION, not a method: `viewkeys(d)`, never `d.viewkeys()`.
    That matters because aliasing it to the unbound `dict.keys` would need
    method-as-a-value support that is not there yet; a def sidesteps it.
    """
    return set(d.keys())


def viewvalues(d):
    return list(d.values())


def viewitems(d):
    return set(d.items())


def with_metaclass(meta, *bases):
    """`six.with_metaclass(meta, *bases)` -- a base class carrying `meta`.

    NOT USABLE YET, and it raises rather than pretending. Two separate reasons,
    and only the second is about this file:

    1. NilPy has no metaclasses, so a `meta` that actually does something cannot
       be honoured at all.
    2. Even for `meta is type` -- which means "no metaclass", and IS the real
       html5lib path, since its `getMetaclass()` returns plain `type` unless the
       debug flag is set -- the corpus spelling is
       `class Phase(with_metaclass(...))`, a class whose base is an EXPRESSION.
       That does not compile here: a base which is a class NAME works, a base
       which is a variable or a call does not.
       See bug-n-a-class-base-that-is-an-expression-does-not-compile.

    So returning `object` for the `meta is type` case would be semantically
    right and still would not compile at the call site -- the wall is (2), not
    (1). Raising keeps this honest until (2) lands, at which point the `type`
    branch below becomes a correct answer rather than a refusal.
    """
    raise NotImplementedError(
        "six.with_metaclass is not supported: NilPy has no metaclasses, and a "
        "class whose base is an expression does not compile yet "
        "(bug-n-a-class-base-that-is-an-expression-does-not-compile)")


def add_metaclass(meta):
    """The decorator form. Same wall, same refusal."""
    raise NotImplementedError(
        "six.add_metaclass is not supported: NilPy has no metaclasses")
