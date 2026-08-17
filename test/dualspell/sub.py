# Reached by BOTH import spellings: the relative `from .sub import C` in this
# package's __init__, and the dotted `from dualspell.sub import C` from the
# importer. CPython compiles and runs this body exactly once for both.
print("body-ran")


class C:
    pass
