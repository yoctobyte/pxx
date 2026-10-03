# SPDX-License-Identifier: 0BSD
"""mimic_urllib -- the PACKAGE `urllib`, which holds no names of its own here.

It exists so `from urllib import <submodule>` resolves: the package has to be
found before its submodule can be. The submodules are their own shims, the flat
siblings mimic_urllib_<sub> (parse, request, error), which is exactly what `import
urllib.<sub>` already reaches; PyPackageSubmoduleKey finds them beside this file.
Nothing is bound here, so `import urllib` followed by `urllib.<sub>.<name>`
is NOT supported -- CPython binds the submodule as an attribute only after it is
imported, and that is the spelling that works: `import urllib.<sub>`.
"""
