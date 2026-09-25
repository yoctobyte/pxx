# `list()`, `bytes()`, `bytearray()` are a construction threaded through
# stamping helpers (pylist_mark_tuple / pylist_mark_list / pybytes_from_list /
# pybytes_mark_bytearray) that hand back the object they were given. The
# hoisted temp owned the construction AND the name bound to a stamp's result
# was taken as a second owner, so every call released the object twice
# (frankb-12; "RELEASE of a FREED object" under -dPXX_HEAP_DEBUG). `set()` is
# the opposite case: the stamp's argument is an UNBOUND construction, so its
# result is the only owner and must not be retained again.
def f():
    b = bytearray()
    c = bytes()
    l = list()
    t = tuple()
    s = set()
    z = frozenset()
    s.add(3)
    return len(b) + len(c) + len(l) + len(t) + len(s) + len(z)
n = 0
for i in range(300):
    n += f()
print(n)
