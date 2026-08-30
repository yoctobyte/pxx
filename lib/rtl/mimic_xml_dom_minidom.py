# WAS PARKED FOR A DAY, AND THE REASON IS WORTH KEEPING.
#
# This file spent 2026-08-30 as `mimic_xml_dom_minidom.py.parked` -- finished,
# differential-green, and deliberately NOT named *.py, because adding it to
# lib/rtl HUNG THE COMPILER FOREVER (100% CPU, flat RSS, no output, no exit).
# A hang is the worst shape a gate failure can take: it does not fail, it
# stops, and any lane running `make lib-test` would have read it as a slow box.
#
# It was NOT reshaped to dodge the hang. Renaming the one local that triggered
# it would have built that same day and hidden the bug -- exactly what the
# platonic-code rule in CLAUDE.md forbids. Instead the bug was filed with a
# 9-line repro (bug-n-a-class-with-two-definitions-of-one-method-hangs-the-
# compiler-forever) and this file waited.
#
# Unparked once the fix could actually be USED here, which is a later moment
# than the fix landing: Track B builds with $(PXX_STABLE), not HEAD, so the
# condition was a PIN containing frankA's 0425a62c8 -- reached at v395
# (acec6c192f14). Verified by compiling this file with the pinned binary, not
# by inferring it from the sha: 2.9s, where v394 spun for a 75s timeout.
#
# SPDX-License-Identifier: 0BSD
"""mimic_xml_dom_minidom -- a real DOM you can build and mutate, not an alias.

Reached as `from xml.dom import minidom`, which resolves through
lib/rtl/mimic_xml_dom.py's `minidom` namespace object. Kept in its OWN file
because mimic_xml_dom.py's header states that it is `xml.dom.Node`'s twelve
constants "and nothing more", and that claim is load-bearing there -- a DOM
bolted into it would falsify the one sentence a reader trusts.

WHY THIS IS AN IMPLEMENTATION AND NOT A SHIM. Every other mimic_ module in this
tree maps names onto something that already exists. There is no DOM here to map
onto, so this file IS the object model: nodes with parents, children, ordering,
attributes and identity, plus the mutations that maintain those invariants. The
ticket (feature-b-a-real-minidom-is-an-implementation-not-a-shim) was split out
of its parent precisely to stop it being ranked alongside alias tables.

SCOPE IS MEASURED OFF THE CALLER, then stated. `html5lib/treebuilders/dom.py`
and its `AttrList` wrapper were read for every attribute and call, rather than
CPython's minidom being transcribed:

  module      getDOMImplementation
  DOMImpl     createDocument, createDocumentType
  Document    createElement, createElementNS, createTextNode, createComment,
              createDocumentFragment, createAttribute, documentElement
  Node        appendChild, insertBefore, removeChild, cloneNode, normalize,
              hasChildNodes, hasAttributes, childNodes, firstChild, parentNode,
              ownerDocument, nodeType, nodeName, nodeValue
  Element     setAttribute, setAttributeNS, attributes, tagName, namespaceURI,
              localName, prefix
  Attr        name, value
  DocumentType  name, publicId, systemId
  NamedNodeMap  keys, values, items, len, [name], [name] = attr, del [name]

Absent from that list and therefore absent here: getElementsByTagName, XPath,
namespaces beyond what the caller sets, serialisation (`toxml`/`writexml`),
parsing (`parseString`/`parse`), entity and notation nodes, and `ownerElement`.
Per devdocs/dev/python-compat-tiers.md a missing name is a compile error at the
use site, which beats an approximation -- and NOTHING here parses XML, so if you
reached for this expecting `minidom.parseString` you want a parser ticket, not
this file.

`_child_node_types` IS DELIBERATELY PRESENT AND IS NOT AN ACCIDENT.
html5lib reaches into it (dom.py:171-175):

    if hasattr(self.dom, '_child_node_types'):
        if TEXT_NODE not in self.dom._child_node_types:
            self.dom._child_node_types = list(self.dom._child_node_types)
            self.dom._child_node_types.append(TEXT_NODE)

That is a caller patching CPython minidom's PRIVATE class-level list of node
types a Document may hold, so the document can carry text. The `hasattr` guard
means the caller knows it is reaching into someone's internals -- and it also
means an implementation WITHOUT this attribute is silently skipped rather than
failing, so the document would then reject text nodes with no clue why. It is
therefore reproduced under its exact private name, as an instance-level list,
because the caller reassigns it on the instance.

DIFFERENTIAL, NOT PLAUSIBILITY. test/lib_mimic_xml_dom_minidom.npy runs
unmodified under CPython against the real minidom and both outputs are compared
byte for byte. That is the gate this file is held to -- see the ticket for why it
is the gate rather than the corpus file: `property(...)` as a builtin name does
not exist in this dialect, which blocks html5lib's dom treebuilder from Track B
entirely and is filed as bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name.
"""

# THE nodeType CONSTANTS ARE LOCAL, AND THAT IS FORCED, NOT PREFERRED.
#
# The obvious spelling is `from xml.dom import Node` and read `TEXT_NODE`.
# It cannot work: `from xml.dom import minidom` is satisfied by mimic_xml_dom.py
# binding a name to THIS module, so mimic_xml_dom already depends on this file.
# Importing xml.dom back from here closes a cycle, and the measured symptom is
# `error: class method not found: TEXT_NODE` at the first use -- a diagnostic
# that names the constant and says nothing about the cycle, which is why this
# comment exists rather than a shrug.
#
# So the values are duplicated, and duplication of a spec table is exactly what
# mimic_xml_dom.py's header warns about. The protection is not care, it is the
# gate: test/lib_mimic_xml_dom_minidom.npy asserts every one of these equals the
# `xml.dom.Node` constant of the same name, under CPython AND under pxx. If a
# value here ever drifts from the canonical table, that test fails; it cannot
# rot quietly. Do not "simplify" those assertions away -- they are the only
# thing making this duplication safe.
#
# Values are the DOM spec's nodeType enumeration, fixed by a published standard.
ELEMENT_NODE = 1
ATTRIBUTE_NODE = 2
TEXT_NODE = 3
COMMENT_NODE = 8
DOCUMENT_NODE = 9
DOCUMENT_TYPE_NODE = 10
DOCUMENT_FRAGMENT_NODE = 11
PROCESSING_INSTRUCTION_NODE = 7


# ---------------------------------------------------------------- exceptions

class DOMException(Exception):
    pass


class HierarchyRequestErr(DOMException):
    pass


class NotFoundErr(DOMException):
    pass


# ------------------------------------------------------------- attribute map

class NamedNodeMap:
    """Element.attributes -- a dict of name -> Attr, in insertion order.

    CPython's NamedNodeMap is richer (item(), getNamedItemNS(), length). Only the
    mapping surface html5lib's AttrList uses is here, plus `length` because it is
    free and every DOM reader looks for it. Insertion order matters: html5lib
    round-trips attributes and a set-ordered map would reorder them, which is a
    difference the differential would catch as changed output rather than as an
    error.
    """

    def __init__(self):
        self._names = []
        self._byname = {}

    def __len__(self):
        return len(self._names)

    def __getitem__(self, name):
        return self._byname[name]

    def __setitem__(self, name, attr):
        if name not in self._byname:
            self._names.append(name)
        self._byname[name] = attr

    def __delitem__(self, name):
        if name not in self._byname:
            raise NotFoundErr(name)
        del self._byname[name]
        self._names.remove(name)

    def __contains__(self, name):
        return name in self._byname

    def __iter__(self):
        return iter(self._names)

    def keys(self):
        return list(self._names)

    def values(self):
        return [self._byname[n] for n in self._names]

    def items(self):
        return [(n, self._byname[n]) for n in self._names]

    @property
    def length(self):
        return len(self._names)


# ------------------------------------------------------------------- nodes

class MiniNode:
    """The node base: parentage, ordering, and the mutations that maintain them.

    Named MiniNode rather than Node so it cannot be confused with
    `xml.dom.Node`, the constants class, which this module imports and uses for
    nodeType values. Two different things that CPython also spells differently,
    and conflating them is how a nodeType comparison silently becomes 0 == 0 --
    see mimic_xml_dom.py's header for the near-miss that lesson comes from.
    """

    def __init__(self, ownerDocument=None):
        self.childNodes = []
        self.parentNode = None
        self.ownerDocument = ownerDocument
        self.nodeValue = None
        self.nodeName = None
        self.nodeType = None

    @property
    def firstChild(self):
        if len(self.childNodes) == 0:
            return None
        return self.childNodes[0]

    @property
    def lastChild(self):
        if len(self.childNodes) == 0:
            return None
        return self.childNodes[len(self.childNodes) - 1]

    def hasChildNodes(self):
        return len(self.childNodes) > 0

    def hasAttributes(self):
        # Overridden by Element. On every other node type CPython answers False
        # rather than raising, and html5lib calls it without checking the type.
        return False

    def appendChild(self, node):
        self._adopt(node)
        self.childNodes.append(node)
        node.parentNode = self
        return node

    def insertBefore(self, node, refChild):
        if refChild is None:
            return self.appendChild(node)
        idx = -1
        i = 0
        for c in self.childNodes:
            if c is refChild:
                idx = i
            i = i + 1
        if idx < 0:
            raise NotFoundErr("insertBefore: refChild is not a child of this node")
        self._adopt(node)
        self.childNodes.insert(idx, node)
        node.parentNode = self
        return node

    def removeChild(self, node):
        idx = -1
        i = 0
        for c in self.childNodes:
            if c is node:
                idx = i
            i = i + 1
        if idx < 0:
            raise NotFoundErr("removeChild: node is not a child of this node")
        del self.childNodes[idx]
        node.parentNode = None
        return node

    def _adopt(self, node):
        """Detach `node` from a previous parent before re-parenting it.

        CPython's minidom does this, and without it a node appended twice would
        appear under both parents -- a tree that is not a tree. html5lib DOES
        move nodes between parents (its insertText and reparenting paths), so
        this is exercised rather than defensive.
        """
        if node.parentNode is not None:
            node.parentNode.removeChild(node)

    def normalize(self):
        """Merge adjacent Text children and drop empty ones, recursively.

        CPython's contract, and worth stating because a no-op `normalize` would
        pass any test that only checks it is callable: adjacent text nodes are
        merged into the first, and a text node whose data is empty is removed.
        """
        merged = []
        for child in self.childNodes:
            if child.nodeType == TEXT_NODE:
                if len(merged) > 0 and merged[len(merged) - 1].nodeType == TEXT_NODE:
                    prev = merged[len(merged) - 1]
                    prev.data = prev.data + child.data
                    prev.nodeValue = prev.data
                    child.parentNode = None
                    continue
                if child.data == "":
                    child.parentNode = None
                    continue
            merged.append(child)
        self.childNodes = merged
        for child in self.childNodes:
            child.normalize()

    def cloneNode(self, deep):
        raise DOMException("cloneNode is not implemented for this node type")

    def _clone_children_into(self, copy, deep):
        if deep:
            for child in self.childNodes:
                copy.appendChild(child.cloneNode(True))
        return copy


class Text(MiniNode):
    def __init__(self, data, ownerDocument=None):
        MiniNode.__init__(self, ownerDocument)
        self.data = data
        self.nodeValue = data
        self.nodeName = "#text"
        self.nodeType = TEXT_NODE

    def cloneNode(self, deep):
        return Text(self.data, self.ownerDocument)


class Comment(MiniNode):
    def __init__(self, data, ownerDocument=None):
        MiniNode.__init__(self, ownerDocument)
        self.data = data
        self.nodeValue = data
        self.nodeName = "#comment"
        self.nodeType = COMMENT_NODE

    def cloneNode(self, deep):
        return Comment(self.data, self.ownerDocument)


class Attr(MiniNode):
    def __init__(self, name, ownerDocument=None, namespaceURI=None, localName=None, prefix=None):
        MiniNode.__init__(self, ownerDocument)
        self.name = name
        self.nodeName = name
        self.value = ""
        self.nodeValue = ""
        self.nodeType = ATTRIBUTE_NODE
        self.namespaceURI = namespaceURI
        self.localName = localName
        self.prefix = prefix

    def cloneNode(self, deep):
        c = Attr(self.name, self.ownerDocument, self.namespaceURI, self.localName, self.prefix)
        c.value = self.value
        c.nodeValue = self.value
        return c


class DocumentFragment(MiniNode):
    def __init__(self, ownerDocument=None):
        MiniNode.__init__(self, ownerDocument)
        self.nodeName = "#document-fragment"
        self.nodeType = DOCUMENT_FRAGMENT_NODE

    def cloneNode(self, deep):
        return self._clone_children_into(DocumentFragment(self.ownerDocument), deep)


class DocumentType(MiniNode):
    def __init__(self, name, publicId, systemId, ownerDocument=None):
        MiniNode.__init__(self, ownerDocument)
        self.name = name
        self.nodeName = name
        self.publicId = publicId
        self.systemId = systemId
        self.nodeType = DOCUMENT_TYPE_NODE

    def cloneNode(self, deep):
        return DocumentType(self.name, self.publicId, self.systemId, self.ownerDocument)


class Element(MiniNode):
    def __init__(self, tagName, ownerDocument=None, namespaceURI=None, localName=None, prefix=None):
        MiniNode.__init__(self, ownerDocument)
        self.tagName = tagName
        self.nodeName = tagName
        self.nodeType = ELEMENT_NODE
        self.namespaceURI = namespaceURI
        self.localName = localName
        self.prefix = prefix
        self.attributes = NamedNodeMap()

    def hasAttributes(self):
        return len(self.attributes) > 0

    def setAttribute(self, name, value):
        a = Attr(name, self.ownerDocument)
        a.value = value
        a.nodeValue = value
        self.attributes[name] = a

    def setAttributeNS(self, namespaceURI, qualifiedName, value):
        """CPython keys the map by QUALIFIED name, not by local name.

        Worth stating because keying by localName would look right and would
        silently collide two attributes that differ only by prefix. html5lib
        writes namespaced attributes through this path and reads them back
        through AttrList's plain-name indexing, so the key must be the one
        CPython uses.
        """
        prefix = None
        localName = qualifiedName
        idx = qualifiedName.find(":")
        if idx >= 0:
            prefix = qualifiedName[0:idx]
            localName = qualifiedName[idx + 1:]
        a = Attr(qualifiedName, self.ownerDocument, namespaceURI, localName, prefix)
        a.value = value
        a.nodeValue = value
        self.attributes[qualifiedName] = a

    def getAttribute(self, name):
        if name in self.attributes:
            return self.attributes[name].value
        return ""

    def cloneNode(self, deep):
        c = Element(self.tagName, self.ownerDocument, self.namespaceURI, self.localName, self.prefix)
        for n in self.attributes.keys():
            c.attributes[n] = self.attributes[n].cloneNode(False)
        return self._clone_children_into(c, deep)


class Document(MiniNode):
    def __init__(self):
        MiniNode.__init__(self, None)
        self.nodeName = "#document"
        self.nodeType = DOCUMENT_NODE
        self.ownerDocument = None
        self.doctype = None
        # See the module header: html5lib patches this private list on the
        # INSTANCE so the document may hold text nodes. Present under its exact
        # CPython name so the caller's hasattr() guard fires.
        self._child_node_types = [ELEMENT_NODE,
                                  PROCESSING_INSTRUCTION_NODE,
                                  COMMENT_NODE,
                                  DOCUMENT_TYPE_NODE]

    @property
    def documentElement(self):
        for c in self.childNodes:
            if c.nodeType == ELEMENT_NODE:
                return c
        return None

    def createElement(self, tagName):
        return Element(tagName, self)

    def createElementNS(self, namespaceURI, qualifiedName):
        prefix = None
        localName = qualifiedName
        idx = qualifiedName.find(":")
        if idx >= 0:
            prefix = qualifiedName[0:idx]
            localName = qualifiedName[idx + 1:]
        return Element(qualifiedName, self, namespaceURI, localName, prefix)

    def createTextNode(self, data):
        return Text(data, self)

    def createComment(self, data):
        return Comment(data, self)

    def createDocumentFragment(self):
        return DocumentFragment(self)

    def createAttribute(self, name):
        return Attr(name, self)

    def cloneNode(self, deep):
        c = Document()
        c.doctype = self.doctype
        return self._clone_children_into(c, deep)


class DOMImplementation:
    def createDocumentType(self, qualifiedName, publicId, systemId):
        return DocumentType(qualifiedName, publicId, systemId, None)

    def createDocument(self, namespaceURI, qualifiedName, doctype):
        """CPython appends the doctype and the root element when given.

        html5lib calls this with (None, None, None) and builds the tree itself,
        so the three-None path is the one the corpus exercises -- but the
        populated path is implemented and asserted anyway, because a
        createDocument that silently ignored its arguments would pass the
        corpus and be wrong for every other caller.
        """
        doc = Document()
        if doctype is not None:
            doc.doctype = doctype
            doc.appendChild(doctype)
        if qualifiedName is not None:
            doc.appendChild(doc.createElementNS(namespaceURI, qualifiedName))
        return doc


_impl = DOMImplementation()


def getDOMImplementation():
    return _impl
