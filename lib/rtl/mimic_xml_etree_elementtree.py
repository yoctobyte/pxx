# SPDX-License-Identifier: 0BSD
"""mimic_xml_etree_elementtree -- ElementTree as a TREE MODEL, with no XML reader.

Reached as `import xml.etree.ElementTree as ET` (or `from xml.etree.ElementTree
import Element`), which the NilPy import resolver maps to this file (dotted
module name -> `mimic_xml_etree_elementtree`) and announces as a shim. Not named
for the upstream package: no file in this tree carries an upstream name.

WHY THERE IS NO PARSER HERE, AND WHY THAT IS THE WHOLE DESIGN.
Decided by the user on 2026-08-19 ("for now the minimal shim; if we want to
extend it we can write the XML importer later",
decide-xml-etree-thin-tree-model-or-a-real-xml-library) on the strength of a
measurement rather than a guess: the only non-test importer in the corpora is
`html5lib/_utils.py`, which does `import xml.etree.ElementTree as default_etree`
and then hands that module to `treebuilders/etree.py` and
`treewalkers/etree.py` as a place to HANG A TREE. html5lib parses the HTML
itself and defines its own `tostring`
(`html5lib/treebuilders/etree.py:262`). There is no XML text on either side of
this interface, in either direction. A parser here would be code nothing calls,
and an XML parser is the kind of thing that gets believed once it exists.

THE ONE IDENTITY THAT HAS TO BE EXACT: `Comment("x").tag` IS `Comment`.
CPython uses the `Comment` factory as its own sentinel tag, and html5lib
depends on it, twice:

    ElementTreeCommentType = ElementTree.Comment("asd").tag   # treewalkers/etree.py:16
    ...                                                       # treebuilders/etree.py:21
    if node.tag == ElementTreeCommentType:

Get it wrong and there is no error anywhere -- comments are simply never
recognised, and the walker emits them as elements whose tag is a function. That
is the failure class this campaign exists to catch, so
test/lib_mimic_xml_etree_elementtree.npy asserts it directly instead of
trusting it to fall out of the constructor.

Measured on pinned v352: the identity html5lib needs (two comments' tags equal
each other, and no element tag equals one) HOLDS. The neighbouring spelling
`Comment("x").tag == Comment` -- comparing against the module-level name --
answers False where CPython answers True, because a NilPy function stored in a
variable is boxed afresh per assignment and equality compares the box
(bug-n-two-references-to-the-same-function-are-not-equal). html5lib never
writes that form, so nothing here is blocked by it; the differential test
records the divergence rather than asserting the wrong answer.

WHAT IS DELIBERATELY ABSENT, AND WHY OMITTED RATHER THAN PRESENT-AND-REFUSING.
The two shapes both exist in this tree: `mimic_urllib_request` includes
`urlopen` and raises, this file omits `parse` entirely. That is not a general
rule -- the user was asked and deliberately left it open -- it is a
measurement. Present-and-refusing exists so code that IMPORTS a name without
CALLING it still compiles; a grep of html5lib, reportlab, tinycss2 and
webencodings finds no reference to `parse`, `fromstring` or `iterparse` on this
module outside tests (reportlab's single hit is a comment about a future
release). Nothing speculative, so omitting them is strictly better: an
unresolved-name error at compile time, at the exact call site, instead of an
exception at run time somewhere downstream.

Absent for that reason: `parse`, `fromstring`, `fromstringlist`, `XMLParser`,
`XMLPullParser`, `iterparse`, `tostring`, `tostringlist`, `write`,
`register_namespace`, `canonicalize`, `indent`, `dump`, `ProcessingInstruction`,
`PI`, `QName`, `SubElement`, `findall`, `findtext`, `iter`, `itertext`.
Also absent: `__repr__` -- CPython's embeds the object's address, so no
definition here could match it, and a plausible-looking fake (`at 0x0`) would
read as real in a log.
`SubElement` and `iter` could be written exactly and are held back only because
nothing calls them: a shim that grows on speculation stops being measurable.

`find` IS here because html5lib calls it (`treebuilders/etree.py:332`), but only
over the path subset that can be answered exactly -- see `_find_one`. Anything
outside that subset RAISES rather than returning None, because a `find` that
answers None for a path it did not understand is indistinguishable from one that
looked and found nothing.
"""


class Element:
    """A node: a tag, optional text and tail, an attribute dict, and children.

    CPython's `Element` is a sequence over its CHILDREN (not its attributes),
    which is why `len(elem)` counts children and `elem[0]` is the first child
    while attributes are reached through `.attrib` / `.get` / `.set`. Code that
    confuses the two is common, and matching upstream exactly is the only
    defence.
    """

    def __init__(self, tag, attrib=None):
        self.tag = tag
        # `.text` is the text BEFORE the first child; `.tail` is the text after
        # this element's closing tag, i.e. it belongs to the parent's content
        # stream. Both are None when absent and never "" -- html5lib tests them
        # with `if not element.tail` and separately assigns "" to start
        # accumulating, so None and "" are distinguishable states upstream.
        self.text = None
        self.tail = None
        # CPython spells the default `attrib={}` and then copies it, so callers
        # never share the literal. Written as None-then-fresh-dict here: same
        # observable behaviour, and it does not rely on when a default argument
        # is evaluated.
        if attrib is None:
            self.attrib = {}
        else:
            self.attrib = dict(attrib)
        self._children = []

    # --- children: the sequence interface ---

    def __len__(self):
        return len(self._children)

    def __getitem__(self, index):
        return self._children[index]

    def __setitem__(self, index, element):
        self._children[index] = element

    def __iter__(self):
        # CPython's C Element carries tp_iter, and its pure-Python Element gets
        # iteration free from `__getitem__`. NilPy does not derive iteration
        # from the sequence protocol
        # (bug-n-for-over-an-object-with-len-and-getitem-does-not-iterate), so
        # it is spelled out. Behaviour is identical either way, which is why
        # this is not registered as a workaround.
        return iter(self._children)

    def append(self, subelement):
        self._children.append(subelement)

    def extend(self, elements):
        for element in elements:
            self._children.append(element)

    def insert(self, index, subelement):
        self._children.insert(index, subelement)

    def remove(self, subelement):
        """Removes by IDENTITY of the child, not by tag, and raises if absent --
        upstream does `self._children.remove(subelement)` and lets ValueError
        out."""
        self._children.remove(subelement)

    def clear(self):
        """Resets the element to empty: children, attributes, text AND tail.
        Upstream clears the tail too, which surprises people, so it is copied
        rather than tidied."""
        self.attrib.clear()
        self._children = []
        self.text = None
        self.tail = None

    # --- attributes ---

    def get(self, key, default=None):
        """An attribute, or `default` -- never a KeyError. This is the reason
        html5lib can ask for `publicId` on an element that has none."""
        if key in self.attrib:
            return self.attrib[key]
        return default

    def set(self, key, value):
        self.attrib[key] = value

    def keys(self):
        return list(self.attrib.keys())

    def items(self):
        return list(self.attrib.items())

    # --- the one path query ---

    def find(self, path, namespaces=None):
        """The first matching subelement, or None if there was none to find.

        Supported: a plain tag (`html`), a fully-qualified tag
        (`{http://www.w3.org/1999/xhtml}html`), `*`, `.`, and any of those
        joined by `/` to walk down. That is what html5lib asks for
        (`treebuilders/etree.py:332`) and it can be answered exactly.

        Everything else -- `//`, `..`, `[predicate]`, `@attr`, `text()` -- RAISES.
        Returning None for a path this shim did not parse would be
        indistinguishable from a genuine no-match, which is the silent-wrong-
        answer shape; a raise names the path and the shim.
        """
        if namespaces is not None:
            raise NotImplementedError(
                "mimic_xml_etree_elementtree: find() takes no namespaces map; "
                "spell the tag as {uri}local instead")
        return _find_path(self, path)


def _find_path(element, path):
    """Walks `path` from `element`, one `/`-separated step at a time."""
    if path == "":
        raise SyntaxError("mimic_xml_etree_elementtree: empty path")
    _reject_unsupported_path(path)
    current = element
    for step in _split_steps(path):
        if step == ".":
            continue
        if step == "":
            # Only reachable as a leading or doubled separator; both are
            # absolute/descendant syntax this shim does not implement.
            raise NotImplementedError(
                "mimic_xml_etree_elementtree: unsupported path " + repr(path))
        current = _find_one(current, step)
        if current is None:
            return None
    if current is element:
        # A path of nothing but "." selects the element itself, as upstream.
        return element
    return current


def _split_steps(path):
    """Splits a path on `/`, but NOT on the slashes inside a `{uri}` brace.

    A plain `path.split("/")` looks right and is wrong: the one qualified tag
    html5lib asks for is `{http://www.w3.org/1999/xhtml}html`, whose URI carries
    three slashes, so the naive split produced four nonsense steps and find()
    answered None. It answered None for the RIGHT path, which is why this is
    spelled out here -- upstream's ElementPath tokenizer is brace-aware for the
    same reason.
    """
    steps = []
    current = ""
    depth = 0
    for ch in path:
        if ch == "{":
            depth = depth + 1
            current += ch
        elif ch == "}":
            depth = depth - 1
            current += ch
        elif ch == "/" and depth == 0:
            steps.append(current)
            current = ""
        else:
            current += ch
    steps.append(current)
    return steps


def _reject_unsupported_path(path):
    """Refuses ElementPath syntax this shim cannot answer, LOUDLY."""
    bad = "[@"
    for ch in bad:
        if ch in path:
            raise NotImplementedError(
                "mimic_xml_etree_elementtree: unsupported path " + repr(path) +
                " (only tag, {uri}tag, *, . and / are implemented)")
    if ".." in path:
        raise NotImplementedError(
            "mimic_xml_etree_elementtree: unsupported path " + repr(path) +
            " (no parent axis)")


def _find_one(element, tag):
    """The first direct child matching one path step, or None."""
    for child in element:
        # `*` matches ANY child, comments included -- measured against CPython,
        # which returns the comment (`find("*")` on a div whose first child is a
        # comment gives the comment, and `findall("*")` lists its tag as the
        # Comment function). The plausible reading, that `*` means "any
        # element", is wrong, and the differential test caught it.
        if tag == "*":
            return child
        if child.tag == tag:
            return child
    return None


def Comment(text=None):
    """A comment node, whose `.tag` is this very function.

    Not a quirk to normalise away: CPython does exactly this, so the factory
    doubles as the sentinel that tells a comment from an element, and html5lib
    captures it once (`ElementTree.Comment("asd").tag`) and compares every
    node's tag against it. The comment's body lives in `.text`, like an
    element's.
    """
    element = Element(Comment)
    element.text = text
    return element


class ElementTree:
    """A wrapper holding one root element.

    Thin on purpose: upstream's ElementTree is where `parse` and `write` live,
    and neither is here. What remains is the root-holder that
    `html5lib/treebuilders/etree.py:268` type-tests with
    `isinstance(element, ElementTree.ElementTree)` and
    `treewalkers/etree.py:40` unwraps with `.getroot()`.

    It deliberately has NO `.tag`: the treewalker distinguishes a tree from an
    element with `hasattr(node, "tag")`, so giving this class one would make
    every tree walk as a tagless element.
    """

    def __init__(self, element=None):
        # `file=` is absent rather than refusing: it exists only to parse, and
        # there is no parser here. See the module docstring on omit-vs-refuse.
        self._root = element

    def getroot(self):
        return self._root

    def _setroot(self, element):
        """Upstream spells this private and html5lib does not call it, but a
        tree built by hand has no other way to acquire a root after
        construction."""
        self._root = element

    def find(self, path, namespaces=None):
        return self._root.find(path, namespaces)
