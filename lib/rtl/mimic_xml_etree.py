# SPDX-License-Identifier: 0BSD
"""mimic_xml_etree -- the PACKAGE `xml.etree`, which holds no names of its own here.

It exists so `from xml.etree import <submodule>` resolves: the package has to be
found before its submodule can be. The submodules are their own shims, the flat
siblings mimic_xml_etree_<sub> (ElementTree), which is exactly what `import
xml.etree.<sub>` already reaches; PyPackageSubmoduleKey finds them beside this file.
Nothing is bound here, so `import xml.etree` followed by `xml.etree.<sub>.<name>`
is NOT supported -- CPython binds the submodule as an attribute only after it is
imported, and that is the spelling that works: `import xml.etree.<sub>`.
"""
