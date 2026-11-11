# `object` as a builtin type value, `object()` as Python's sentinel, and
# isinstance(x, object). All three were refused (undefined variable / unknown
# type in isinstance). bug-n-object-is-the-one-builtin-type-name-that-is-not-a-value
_MISSING = object()
other = object()
print(_MISSING is _MISSING, _MISSING is other, _MISSING == _MISSING, _MISSING == other)
d = {"a": 1}
v = d.get("b", _MISSING)
print(v is _MISSING, d.get("a", _MISSING) is _MISSING)
print(isinstance(3, object), isinstance("a", object), isinstance(_MISSING, object))
B = object
print(B.__name__, type(_MISSING).__name__, type(_MISSING) is object)
print(repr(_MISSING).startswith("<object object at 0x"))
c = B()
print(c is _MISSING, isinstance(c, B))
class C(object):
    pass
print(isinstance(C(), object), isinstance(C(), (int, object)))
print(str(object))
def f(x=_MISSING):
    return "unset" if x is _MISSING else x
print(f(), f(5))
class K:
    _s = object()
    def chk(self, v):
        return v is K._s
k = K()
print(k.chk(K._s), k.chk(1))
m = {"x": object()}
print(isinstance(m["x"], object), m["x"] is m["x"])
xs = [object() for _ in range(3)]
print(len(set(id(o) for o in xs)))
