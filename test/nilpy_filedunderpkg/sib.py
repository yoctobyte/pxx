# Reached by a RELATIVE import, so the package is compiled under the bare name
# `inner` as well as the dotted `nilpy_filedunderpkg_inner`. Its only job is to
# make the test's outcome depend on which spelling arrived first -- see the
# import ORDER note in test_nilpy_file_dunder_package.npy.
from . import inner


def viasib():
    return inner.probe()
