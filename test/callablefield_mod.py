# Helper for test_nilpy_callable_field_wide_arity.npy. The receiver's class must
# live in ANOTHER module and be reached through a container, because that is what
# makes the receiver dynamically typed while leaving its class visible as a
# CANDIDATE -- the arrangement that reaches PyVariantFieldCallArm's ladder. A
# receiver the frontend can type (`o = make()`, or a parameter with one call
# site) is dispatched statically and never goes near either arm under test.

sink = []


def f4(a, b, c, d):
    return "f4:%s" % ((a, b, c, d),)


def f5(a, b, c, d, e):
    return "f5:%s" % ((a, b, c, d, e),)


def f6(a, b, c, d, e, f):
    return "f6:%s" % ((a, b, c, d, e, f),)


def f7(a, b, c, d, e, f, g):
    return "f7:%s" % ((a, b, c, d, e, f, g),)


def f8(a, b, c, d, e, f, g, h):
    return "f8:%s" % ((a, b, c, d, e, f, g, h),)


# A `-> None` function is a real Pascal PROCEDURE and has its own
# function-pointer type; casting one through the function types reads a garbage
# hidden-result pointer and the callee's epilogue writes through it. It needs its
# own row or that carrier stays unexercised.
def v5(a, b, c, d, e):
    sink.append(("v5", a, b, c, d, e))


def v8(a, b, c, d, e, f, g, h):
    sink.append(("v8", a, b, c, d, e, f, g, h))


class Tagged:
    def __init__(self, tag):
        self.tag = tag

    def m5(self, a, b, c, d, e):
        return "m5:%s:%s" % (self.tag, (a, b, c, d, e))


class Box:
    """Callable FIELDS, not methods -- the attribute holds a function VALUE."""

    def __init__(self, tag):
        self.tag = tag
        self.c4 = f4
        self.c5 = f5
        self.c6 = f6
        self.c7 = f7
        self.c8 = f8
        self.cv5 = v5
        self.cv8 = v8
        # A lambda's value is a closure OBJECT, not a code address, and it takes
        # the interpreted road, which never had an arity cap. Its row is here to
        # keep the universal dispatcher honest across carriers, not to pin a cap.
        self.clam = lambda a, b, c, d, e, f: "clam:%s:%s" % (
            tag, (a, b, c, d, e, f))
        # A BOUND METHOD stored in a field: a fourth carrier, its own pointer
        # type again. Built from the PARAMETER rather than a literal, which is
        # the combination of the two defects fixed that day: until
        # bug-n-a-bound-method-stored-in-a-field-from-a-parameterised-receiver-
        # is-not-callable, `Tagged(tag).m5` registered no field at all and died
        # with `object is not callable` at ANY arity, and the wide-arity cap
        # here reported its own refusal first and hid it. This row needs BOTH
        # fixes; test_nilpy_bound_method_field_from_expression pins the other
        # one alone, at one argument.
        self.cm5 = Tagged(tag).m5


class Other:
    """A SECOND candidate class declaring the same field names, so the arm is
    emitted once per candidate and the run-time class picks between them."""

    def __init__(self):
        self.c5 = f5
        self.c8 = f8


def boxes(tag):
    return [Box(tag)]


def others():
    return [Other()]


def drain():
    out = list(sink)
    del sink[:]
    return out
