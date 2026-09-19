# `from . import NAME` where NAME is defined HERE, not a submodule file.
# test_nilpy_relative_import_of_an_init_member.npy
NAME = "relmember"
LIMIT = 7


def run(x: int) -> int:
    return x * 2
