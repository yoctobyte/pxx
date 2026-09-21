# Declares `wind` as a DATA FIELD and `gust` not at all. `env` is unannotated,
# so the receiver is a variant and the call is dispatched at run time.
#
# THE FIELD IS INITIALISED TO None ON PURPOSE -- this is the ticket's `v8` row.
# The first diagnosis of this defect was that an unresolvable assignment WIDENED
# the field to a variant and the widened field then satisfied the callable-field
# fallback, a self-fulfilling loop, and the proposed fix was a sentinel marking a
# widened field. v8 refutes that: `= None` is variant from birth, nothing widens,
# and it failed identically. `= None` is also the ORDINARY way to write the
# field, so the sentinel fix would have repaired the rarer spelling. The row is
# here so nobody re-derives it.
class Craft:
    def __init__(self):
        self.wind = None

    def update(self, env):
        self.wind = env.wind(1.0, 2.0)
        return self.wind

    def peek(self, env):
        # The same call with the result going to a LOCAL rather than to the
        # shadowing field. This one WARNED and was correct even before the fix,
        # so it is the row that names the repair rather than the defect.
        w = env.wind(3.0, 4.0)
        return w

    def gusty(self, env):
        return env.gust(4.0)


# THE MUST-NOT-BREAK POPULATION: a genuine dispatch table. `cb` is None at
# birth and armed with a module-level def, and the receiver really IS the
# candidate class, so the `is` test matches and the DIRECT arm runs. A fix that
# routed every call to the dynamic dispatcher would pass every row above and
# lose this one, which is the whole reason it is in the same fixture.
class Wired:
    def __init__(self):
        self.cb = None


def _double(t):
    return t * 2


def fire(t):
    return t.cb(21)


def through_table():
    w = Wired()
    w.cb = _double
    return fire(w)


# THE RESULT-KIND ROWS, and they use the BARE `return <dyn call>` spelling on
# purpose. Measured on the defect: `print(o.m(1))` inline and `x = o.m(1)` were
# both CORRECT in the same program, and only `return` was wrong -- the loss was
# in the enclosing def's inferred RETURN type, not in the call node, which the
# frontend had already tagged tyVariant. So a row that assigns to a local first
# does not test this and the two spellings above are already covered by `peek`.
class Kinds:
    def ret_float(self, env):
        return env.kind_float(77)

    def ret_str(self, env):
        return env.kind_str(1)

    def ret_list(self, env):
        return env.kind_list(1)

    def ret_dict(self, env):
        return env.kind_dict(1)

    def ret_int(self, env):
        # THE ROW THAT CANNOT FAIL, kept and LABELLED as such. The defect
        # coerced the result to an integer, so an int result survived it --
        # correct for the wrong reason. An int-only fixture passes on the
        # unfixed compiler, which is why the four rows above exist. This one is
        # here as the collision, not as evidence.
        return env.kind_int(1)
