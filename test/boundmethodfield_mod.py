# Helper for test_nilpy_bound_method_field_from_expression.npy. The receiver's
# class lives here and is reached through a CONTAINER so the call is dispatched
# on the receiver rather than statically -- see that fixture's header.

G = "G"


class Tagged:
    def __init__(self, tag):
        self.tag = tag

    def m1(self, a):
        return "m1:%s:%s" % (self.tag, a)

    def vm(self, a):
        return "vm:%s:%s" % (self.tag, a)


class Holder:
    """Each field stores a BOUND METHOD taken off a freshly constructed
    receiver. The four spellings differ ONLY in what the constructor's argument
    is, which is the axis that decided whether the field was registered."""

    def __init__(self, tag):
        self.tag = tag
        self.lit = Tagged("L").m1          # a string literal -- this one worked
        self.num = Tagged(7).m1            # an int literal -- worked
        self.glb = Tagged(G).m1            # a module global -- did not
        self.par = Tagged(tag).m1          # a parameter -- did not
        self.att = Tagged(self.tag).m1     # its own attribute -- did not
        # Bound off a LOCAL instead of directly off the construction: a
        # different arm of the same scan, which always worked. Its row is the
        # control that says the receiver expression is not what decides it.
        t = Tagged(tag)
        self.loc = t.m1


def holders(tag):
    return [Holder(tag)]
