# THE DEAD ARM. Nothing in here may reach the program: the guarded import above
# it fails, so CPython never executes this module's binding at all. Every name
# is spelled WRONG on purpose, so a regression cannot produce a right answer.
NAME = "ctypes-arm-WRONG"


def only_in_ctypes():
    return "DEAD-ARM-WRONG"
