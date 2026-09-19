# A second module, imported by alias into
# test_nilpy_a_field_from_another_module_s_global.npy. It deliberately does NOT
# re-export fieldglobal_mod's names: a same-named global in two modules is the
# value-side flat-scope defect,
# bug-n-a-from-import-alias-resolves-its-source-through-flat-scope, which the
# field pre-pass no longer shares but the value door still does.
TIDE = "sea"


def helper2(n):
    return n + 1
