# Helper for test_nilpy_a_module_member_named_like_a_pascal_keyword.
#
# Every name here is a word Pascal RESERVES and Python does not, so each one is
# a perfectly ordinary Python function that the unit-qualified member lookup
# used to rewrite to a trailing-underscore spelling this module never declares.
# The values are deliberately not 0, 1, -1 or any width: a blank answer cannot
# be mistaken for a correct one.

def set(x):
    return x * 10 + 1

def type(x):
    return x * 10 + 2

def label(x):
    return x * 10 + 3

def record(x):
    return x * 10 + 4

def array(x):
    return x * 10 + 5

def end(x):
    return x * 10 + 6

def div(x):
    return x * 10 + 7

def mod(x):
    return x * 10 + 8

def string(x):
    return x * 10 + 9

def file(x):
    return x * 100 + 11

def text(x):
    return x * 100 + 12

# `inherited` never reached the member lookup at all -- the qualified form took
# the Pascal `inherited` CONSTRUCT arm and said "inherited call outside method",
# so it is a different defect wearing the same symptom.
def inherited(x):
    return x * 100 + 13

# The ORDERING row, and it is the load-bearing one. `set` above is declared
# plainly; this declares the underscored spelling TOO. That pair is the only
# arrangement that can tell which spelling the lookup prefers -- with just one of
# them present, either order passes and the test certifies nothing. CPython
# answers the plain `set` for `.set`, so pxx must as well, and `.set_` must still
# reach this one.
def set_(x):
    return x * 1000 + 77

# A member that is not a reserved word anywhere, so the row proves the harness
# is reaching this module at all rather than reporting a uniform failure.
def ordinary(x):
    return x * 100 + 99
