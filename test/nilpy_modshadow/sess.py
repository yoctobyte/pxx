"""A module that defines names the builtins already have.

Python namespaces are per module: these REPLACE the builtins inside this
file, and nowhere else. `len` and `sorted` are defined BELOW the def that
calls them, which is the order that typed the caller's result from the
builtin's (bug-n-a-def-in-an-imported-module-does-not-shadow-len-or-sorted).
"""


class Session:
    def __init__(self, region):
        self.region = region


def format(it):
    return "region %s" % it.region


def str(x):
    return "S<%s>" % x


def open(what):
    return "opened %s" % what


def save(it):
    """The bare calls that have to reach THIS module's defs, not pylib's."""
    return format(it) + " / " + str(7) + " / " + open("nothing")


def measure(x):
    """Calls len/sorted ABOVE their defs: the callers' result types must come
    from this module's defs, not from the builtins'."""
    return len(x) + " / " + sorted(x)


def len(x):
    return "L<%s>" % x


def sorted(x):
    return "sorted-by-module"


def counted(x):
    return len(x)
