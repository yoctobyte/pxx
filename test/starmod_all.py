# Helper for test_nilpy_from_import_star.npy: __all__ names what `import *`
# binds. `max` is listed and shadows the builtin; `sum` is not listed, so the
# importer's sum stays the builtin.
__all__ = ["listed", "max"]


def listed():
    return "listed"


def max(a, b):
    return "module max"


def sum(xs):
    return "module sum"
