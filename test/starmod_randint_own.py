# A module with its OWN randint and no star import: the importer's
# `from random import *` must not reach in here.
def randint(a, b):
    return -1


def use():
    return randint(1, 2)
