# SPDX-License-Identifier: 0BSD
"""mimic_warnings -- the `warnings` module surface the NilPy corpora use.

Reached as `import warnings`, which the NilPy import resolver maps here and
announces (`note: warnings -> mimic_warnings (shim, subset)`). Not named
`warnings.py`: no file in this tree carries an upstream name, so the tree says
what a thing is and `--no-shims` can refuse the whole category by the `mimic_`
mapping rather than by a list of names.

THE CATEGORIES ARE NOT HERE, AND CANNOT BE. `Warning`, `UserWarning`,
`DeprecationWarning` and the rest are BUILTINS in CPython, not members of this
module -- calling code names them bare, and overwhelmingly SUBCLASSES them
(`class DataLossWarning(UserWarning)`). They live in compiler/builtin/pylib.pas
(bug-n-the-builtin-warning-exception-hierarchy-is-missing). This module only
provides the reporting surface.

SCOPE IS MEASURED. Across html5lib, tinycss2 and webencodings, non-test code
imports `warnings` in exactly three files and calls exactly one thing:
`warnings.warn(msg, Category)`, 16 times. `simplefilter`, `catch_warnings` and
`resetwarnings` appear only in those projects' own test suites -- they are
provided here anyway because they are a few lines each and a library that calls
one of them should not die on an AttributeError, but nothing in the measured
corpus exercises them.
"""

import sys

# Which (category, message) pairs have already been reported. See warn().
_seen = {}


def warn(message, category=None, stacklevel=1, source=None):
    """`warnings.warn(message, category)` -- report once, to stderr.

    TWO DELIBERATE DIVERGENCES FROM CPython, both forced and both visible:

    1. NO SOURCE LOCATION. CPython prints
       `<file>:<line>: <Category>: <message>` followed by the offending source
       line, because it walks the call stack. There is no frame introspection
       here, so this prints `<Category>: <message>` and stops. The message and
       the category -- the two things the caller chose -- are exact.

    2. DEDUPED BY (category, message), NOT BY LOCATION. CPython's default
       filter reports a given warning once per call site: measured, a warn() in
       a three-iteration loop prints once. Without a location the closest
       analogue is the text itself, which matches CPython for the common case
       (the same message repeated) and differs when one message is warned from
       two different places -- CPython prints twice, this prints once. Printing
       every time was the alternative and it is further from CPython, not
       closer: it turns a loop into a flood.

    `category=None` rather than `category=UserWarning` is a WORKAROUND, not the
    intended signature: a type as a default parameter value segfaults the moment
    the default is taken -- silently, exit 139, no diagnostic
    (bug-n-a-type-as-a-default-parameter-value-segfaults-when-the-default-is-taken,
    registered in devdocs/dev/track-b-workarounds.md). Revert to
    `category=UserWarning` and delete the substitution below when that lands.
    The observable difference is confined to an explicit `warn(msg, None)`,
    which CPython rejects and this accepts -- laxer, which is the direction this
    dialect is allowed to differ in.
    """
    if category is None:
        category = UserWarning
    name = category.__name__
    key = name + ":" + str(message)
    if key in _seen:
        return
    _seen[key] = True
    print(name + ": " + str(message), file=sys.stderr)


def simplefilter(action, category=None, lineno=0, append=False):
    """Accepted and ignored -- there is no filter machinery to configure.

    A no-op rather than a refusal on purpose: every real use is a library or a
    test asking for MORE warnings ("always", "error") or fewer ("ignore"), and
    dying on the request would break code whose actual work is unrelated. What
    it costs is that `simplefilter("error")` does not turn warnings into
    exceptions -- nothing in the measured corpus asks for that.
    """
    return None


def filterwarnings(action, message="", category=None, module="", lineno=0,
                   append=False):
    """Same as simplefilter: accepted, ignored."""
    return None


def resetwarnings():
    """Drop the once-per-message registry, so previously reported warnings
    report again. That is the part of CPython's resetwarnings() this module can
    honour -- there are no filters to clear."""
    _seen.clear()


class catch_warnings:
    """`with warnings.catch_warnings():` -- restores the report registry on exit.

    CPython saves and restores the filter list and each module's
    `__warningregistry__`. There are no filters here, so what is saved and
    restored is the once-per-message registry: warnings reported inside the
    block do not suppress the same message after it. That is the behaviour a
    caller is actually relying on when it wraps something in this.

    `record=True` (returning a list of captured warnings) is NOT supported and
    says so, rather than handing back an empty list that would read as "no
    warnings were raised" -- a silent wrong answer in exactly the place someone
    is asserting on it.
    """

    def __init__(self, record=False, module=None, action=None, category=None,
                 lineno=0, append=False):
        if record:
            raise NotImplementedError(
                "warnings.catch_warnings(record=True) is not supported: this "
                "shim reports to stderr and does not capture warning objects")
        self._saved = None

    def __enter__(self):
        self._saved = dict(_seen)
        return self

    def __exit__(self, exc_type, exc_value, tb):
        _seen.clear()
        for k in self._saved:
            _seen[k] = True
        return False
