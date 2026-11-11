# Taking `obj.__repr__` as a VALUE inside a def made repr() of that class
# SEGFAULT everywhere, before the def ever ran: the frame went variant while
# the signature (and every caller) kept the str result a str dunder has.
# bug-n-a-repr-dunder-taken-as-a-value-segfaults-repr
class Node:
    def __init__(self, v):
        self.v = v
    def __repr__(self):
        return "Node(" + repr(self.v) + ")"
    def __str__(self):
        return "N%d" % self.v

def bound():
    m = Node(5).__repr__
    return m()

def bound_str():
    s = Node(6).__str__
    return s()

print(repr(Node(2)), str(Node(3)), [Node(1), Node(2)])
print(bound(), bound_str())
