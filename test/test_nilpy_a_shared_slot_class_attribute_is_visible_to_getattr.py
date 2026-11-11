# A class attribute lowered as a SHARED SLOT (the class is used as a value,
# H2 = H) has no instance field; hasattr/getattr must find it through the
# receiver's runtime class, on a typed and on a variant receiver.
# bug-n-a-shared-slot-class-attribute-is-invisible-to-the-dynamic-getter
class H:
    K = 7
    def __init__(self):
        self.a = 1
class S(H):
    K = 9
H2 = H
objs = [H(), S(), H2()]
for o in objs:
    print(hasattr(o, "K"), getattr(o, "K", None), getattr(o, "Z", "dflt"), o.K)
def f(o):
    return getattr(o, "K")
print(f(objs[0]), f(objs[1]))
H.K = 3
print([getattr(o, "K") for o in objs])
try:
    getattr(objs[0], "nope")
except AttributeError as e:
    print("AttributeError", e)
h = H()
print(hasattr(h, "K"), getattr(h, "K", None), h.__class__.K)
