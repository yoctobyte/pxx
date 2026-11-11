# `type(self)(args)` -- Python's other spelling of `self.__class__(args)`:
# keywords and defaults reach the constructor, and a SUBCLASS instance
# builds the subclass. feature-n-type-of-self-cannot-be-called-as-a-constructor
class R:
    def __init__(self, x, scale=10):
        self.v = x * scale
    def again(self):
        return type(self)(self.v, scale=2)
    def plain(self):
        return type(self)(1)

class S(R):
    def tag(self):
        return "S"

print(R(3).again().v)
print(R(3).plain().v)
s = S(1).again()
print(type(s).__name__, s.v, s.tag())
r = R(2)
k = type(r)(5)
print(k.v, type(k) is R)
