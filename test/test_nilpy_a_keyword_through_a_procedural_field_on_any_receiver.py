# A keyword argument to a callable FIELD, whatever the receiver: a name, a call
# result, a constructor call, a subscript. bug-n-a-keyword-argument-through-a-procedural-field-needs-a-plain-receiver

def named(a, b=10):
    return a + b


class H:
    def __init__(self):
        self.fn = named


def g():
    return H()


h = H()
print(h.fn(1, b=2))
print(g().fn(1, b=2))
print(H().fn(1, b=2))
hs = [H()]
print(hs[0].fn(1, b=2))
print(H().fn(4))
