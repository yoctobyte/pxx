# The second error class, and it is deliberately NOT an import error: a soft
# import miss inside a pulled module is absorbed by the machinery under test, so
# a fixture built only from those would pass while the bug was live. An
# undefined name is not absorbed by anything.
SHARED = undefined_name_xyz_9f21


def who():
    return "deadname"
