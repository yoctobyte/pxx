# SPDX-License-Identifier: 0BSD
"""mimic_xml_dom -- `xml.dom.Node`'s nodeType enumeration, and nothing more.

Reached as `from xml.dom import Node`, which the NilPy import resolver maps to
this file (dotted module name -> `mimic_xml_dom`) and announces as a shim. Not
named for the upstream package: no file in this tree carries an upstream name.

WHY THIS ONE IS GENUINELY COMPLETE, AND WHY THAT IS NOT THE POINT.
`xml.dom.Node` has twelve integer constants and ZERO methods -- read off
CPython, not off the call sites, because a table built from call sites does not
announce what it omitted. It is the DOM spec's nodeType enumeration, fixed by a
published standard with no version drift, so this is the whole class rather
than a subset of it.

That completeness is exactly what made this file dangerous to write, and it was
refused twice before it was written:

  * On 2026-08-17 it was refused because it unblocked ZERO files -- all four
    victims of the `xml_dom` ladder row landed straight onto the next wall.
  * It was refused AGAIN because of a compiler bug found while measuring: a
    class whose module has no trailing statement lost its attribute
    initialisers and read every one back as 0
    (bug-n-the-last-class-in-a-module-reads-every-attribute-as-zero, fixed
    2026-08-18 in 12275b26f). A constants-only class is precisely that shape.
    So this file -- 20 lines, spec-exact, complete -- would have compiled,
    imported cleanly, and made every `nodeType` comparison in html5lib's
    treewalkers `0 == 0`. Every node would take the first branch and the walker
    would emit structurally wrong output with no error anywhere.

The lesson is written here rather than in a ticket because this file is where
someone will look: **completeness was never the protection.** Verify the
VALUES, not that the import resolves -- resolving is exactly what it did while
answering zero. test/lib_mimic_xml_dom.npy asserts `TEXT_NODE == 3` against
CPython for that reason, and its assertions are load-bearing.

BLOCKED FIVE TIMES BEFORE IT LANDED, AND THE LAST ONE WAS NOT ABOUT THIS FILE.
As of v349, `from xml.dom import Node` then `Node.TEXT_NODE` did not compile:
`ConsumeUnitQualifier` was eating `Node` as a unit qualifier and then looking
`TEXT_NODE` up as a bare symbol, which is why the diagnostic named the
ATTRIBUTE and read as a class-attribute fault to everyone who looked at it. The
guard that should have skipped that for a class looked the unit up by the name
the SOURCE wrote, so for a shim it searched the bare module name, found nothing,
and stood down for every shim there is
(bug-n-from-a-shim-import-a-class-loses-its-class-level-attributes, fixed in
6cd63b836, reaching Track B in pin v350). Landed and gated from v350.

DELIBERATELY ABSENT: `minidom`. `html5lib/treebuilders/dom.py` wants a real DOM
-- ~25 methods, document construction and mutation, plus a reach into minidom's
PRIVATE `_child_node_types` to allow text nodes as children of the document.
That is an implementation, not a shim, and it is filed separately rather than
allowed to ride along under this file's name. Also absent: the DOM exception
hierarchy (`DOMException` and its ~15 subclasses) -- nothing in the corpora
raises or catches one, and a caller who does gets a loud unresolved-name error
instead of an exception that is silently the wrong class.
"""


class Node:
    """The DOM nodeType enumeration. Twelve constants, no methods -- upstream
    has none either, so there is nothing here that was left out."""

    ELEMENT_NODE = 1
    ATTRIBUTE_NODE = 2
    TEXT_NODE = 3
    CDATA_SECTION_NODE = 4
    ENTITY_REFERENCE_NODE = 5
    ENTITY_NODE = 6
    PROCESSING_INSTRUCTION_NODE = 7
    COMMENT_NODE = 8
    DOCUMENT_NODE = 9
    DOCUMENT_TYPE_NODE = 10
    DOCUMENT_FRAGMENT_NODE = 11
    NOTATION_NODE = 12


# The namespace URIs `xml.dom` publishes alongside Node. Fixed by the XML
# specs, so exact rather than approximate. EMPTY_NAMESPACE is None in CPython
# -- deliberately None and not "", because DOM code tests it with `is None`.
EMPTY_NAMESPACE = None
XML_NAMESPACE = "http://www.w3.org/XML/1998/namespace"
XMLNS_NAMESPACE = "http://www.w3.org/2000/xmlns/"
XHTML_NAMESPACE = "http://www.w3.org/1999/xhtml"
