# A shim fixture for feature-a-the-shim-slot-should-find-a-python-shaped-shim.
#
# The name is deliberate: /usr/include/search.h EXISTS, so `import search` is a
# name that collides with a host C header. That collision is the whole point —
# it is the one case where "is there a shim?" is asked, and asking it about
# `.pas` alone let the header win over a Python-shaped shim.
#
# Python-shaped on purpose too: these are the aliases (`six`-style) that a
# Pascal unit cannot express, which is why the slot had to learn `.py` at all.
text_type = str
PY3 = True


def found():
    return "py-shim"
