# __name__ on a def name, on a def/nested def/lambda held as a value, hasattr,
# and the name in repr(). bug-n-a-function-value-has-no-name

def size(t):
    return t


def mk():
    def inner(x):
        return x
    return inner


print(size.__name__)
f = size
print(f.__name__)
g = mk()
print(g.__name__)
h = lambda x: x
print(h.__name__)
print(repr(size)[:14])
print(hasattr(f, "__name__"), mk.__name__.upper())


class K:
    def m(self):
        return 1


print(K.__name__)
