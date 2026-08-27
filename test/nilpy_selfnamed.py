# Imported by test_nilpy_module_member_named_like_its_module.npy. Ends with a
# rebinding of its OWN module name — the shape CPython's Lib/bisect.py has
# (`bisect = bisect_right`), and the one that made every QUALIFIED access to the
# module's other members fail.
def left(a):
    return "left:" + str(a)


def right(a):
    return "right:" + str(a)


def uses_own_name(a):
    # inside the module, its own binding is what `nilpy_selfnamed` means —
    # Python's rule, and the one this must not break
    return nilpy_selfnamed(a)


nilpy_selfnamed = right
