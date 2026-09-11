# A module whose import is expected to FAIL, so that the diagnostic can be
# checked for its `in:` line. The error is a plain undefined name, chosen
# because it is the shape a reader actually meets and because it needs no
# other feature to reproduce.
#
# THE LINE NUMBER HERE IS NOT PINNED and must not be: the Makefile row asserts
# the PATH. What made this bug expensive was a line number with no file beside
# it, so pinning one here would be the same mistake in the test.
def boom():
    return this_name_is_not_defined_anywhere
