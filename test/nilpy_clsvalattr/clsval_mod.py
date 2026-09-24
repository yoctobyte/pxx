"""A docstring, an assignment, a def and an import all PRECEDE the classes:
each one alone used to put the classref read below on the crashing path."""
import sys

B = 5


def helper():
    return 1


class Bbb:
    V = 1
    W = "w"


class Index(Bbb):
    V = 2
