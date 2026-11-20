# bytes()/bytearray() of a user object implementing the iteration protocol
# take its ints, as CPython does. They raised "cannot convert this value to
# bytes without an encoding": the Variant overload knew lists, ranges and
# cursors but not a user class.
# bug-n-a-user-iterator-into-some-shims-and-builtins-crashes-or-answers-wrong

class Ctr:
    def __init__(self, n):
        self.n = n
        self.i = 0
    def __iter__(self):
        return self
    def __next__(self):
        if self.i >= self.n:
            raise StopIteration
        self.i += 1
        return self.i + 64

class Seq:
    def __init__(self, items):
        self.items = items
    def __getitem__(self, i):
        return self.items[i]

print(bytes(Ctr(3)))
print(bytearray(Ctr(2)))
print(bytes(Seq([104, 105])))
v = Ctr(2)
print(bytes(v), bytes(v))
try:
    bytearray(Seq([300]))
except ValueError as e:
    print("ValueError")
