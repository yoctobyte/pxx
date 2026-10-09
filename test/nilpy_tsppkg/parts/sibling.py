# A SECOND importer of vec.first, after a sibling (earth) has re-exported it:
# flat lookup found earth's re-export VAR first, this module bound to it, and
# called the typed def through it dynamically -- a segfault (TSP).
from . import earth
from .vec import first


def g() -> float:
    return first((9.0, 1.0)) + earth.f1()
