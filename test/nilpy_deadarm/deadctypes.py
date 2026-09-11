# VALID Python that cannot compile under NilPy: `ctypes` binds nothing, so the
# member read below is `no member c_uint came of the qualifier ctypes`. This is
# lekkerzeilen/platform/_ctypes_backend.py in three lines, and CPython never
# imports it because the arm that names it is dead.
import ctypes

SHARED = ctypes.c_uint


def who():
    return "deadctypes"
