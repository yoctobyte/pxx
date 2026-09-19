# Package for test_nilpy_from_a_package_import_a_submodule.npy. Its __init__
# does NOT import geo, units or deep: `from nilpy_subimp import geo` has to
# find them as submodules. `label` is a def HERE, so it must stay the member.
NAME = "subimp"


def label():
    return "init-label"
