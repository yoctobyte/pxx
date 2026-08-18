# SPDX-License-Identifier: 0BSD
"""mimic_xml_sax_xmlreader -- the SAX `AttributesNSImpl` attribute container.

Reached as `from xml.sax.xmlreader import AttributesNSImpl`, which the NilPy
import resolver maps to this file (dotted module name ->
`mimic_xml_sax_xmlreader`) and announces as a shim. Not named for the upstream
package: no file in this tree carries an upstream name.

WHAT IS HERE AND WHAT IS NOT. `xml.sax.xmlreader` is mostly the parser-side
machinery -- `XMLReader`, `IncrementalParser`, `InputSource`, `Locator` -- which
is a parser, not a shim. What is here is the two attribute containers, which are
the module's only *data* classes: plain dictionary wrappers with a fixed
interface and no parser behind them, so they can be written exactly rather than
approximated. Everything else is absent and fails loudly on use.

WHY A PRODUCER NEEDS THEM. These classes are not just for parsers: code that
FEEDS a SAX handler has to hand it an attributes object, and the handler will
call this interface on it. `html5lib/treeadapters/sax.py` does exactly that --
it constructs `AttributesNSImpl(token["data"], unadjustForeignAttributes)` and
passes it to someone else's `startElementNS`. The handler is arbitrary user
code, so the whole documented interface has to be present, not the two methods
html5lib happens to reach for: an absent `getValueByQName` would surface as an
error inside the *caller's* handler, which is the "looks present, fails deep
inside a caller" shape this campaign exists to avoid.

THE NS KEYING IS THE PART TO GET RIGHT. In `AttributesNSImpl` a name is the
PAIR `(namespace_uri, localname)`, not a string, and `qnames` maps that pair to
the prefixed spelling (`xlink:href`). So `getValue(("uri", "href"))` and
`getValueByQName("xlink:href")` reach the same attribute by different keys, and
`getNameByQName` inverts the qnames table. A shim keyed on plain strings would
work for every unprefixed attribute -- which is nearly all of them -- and fail
only on namespaced ones, i.e. exactly the case the NS variant exists for.
"""


class AttributesImpl:
    """The non-namespace attribute container: names are plain strings.

    CPython's version stores one dict and answers everything from it. Included
    because `AttributesNSImpl` derives from it upstream and a caller that has a
    non-NS handler will construct this one directly.
    """

    def __init__(self, attrs):
        self._attrs = attrs

    def getLength(self):
        return len(self._attrs)

    def getType(self, name):
        """SAX reports an untyped attribute as CDATA; without a DTD that is
        every attribute, so this is the whole truth rather than a stub."""
        return "CDATA"

    def getValue(self, name):
        return self._attrs[name]

    def getValueByQName(self, name):
        return self._attrs[name]

    def getNameByQName(self, name):
        if name not in self._attrs:
            raise KeyError(name)
        return name

    def getQNameByName(self, name):
        if name not in self._attrs:
            raise KeyError(name)
        return name

    def getNames(self):
        return list(self._attrs.keys())

    def getQNames(self):
        return list(self._attrs.keys())

    def __len__(self):
        return len(self._attrs)

    def __getitem__(self, name):
        return self._attrs[name]

    def keys(self):
        return list(self._attrs.keys())

    def __contains__(self, name):
        return name in self._attrs

    def get(self, name, alternative=None):
        if name in self._attrs:
            return self._attrs[name]
        return alternative

    def copy(self):
        # CPython writes `self.__class__(self._attrs)`. Naming the class
        # explicitly is a WORKAROUND, not a preference: calling `__class__` as a
        # constructor does not compile
        # (bug-n-self-__class__-cannot-be-called-as-a-constructor; reading
        # `self.__class__.__name__` is fine, only the call form fails).
        # Registered in devdocs/dev/track-b-workarounds.md -- revert to the
        # __class__ form when that lands, since only that form gives a subclass
        # back an instance of itself.
        return AttributesImpl(self._attrs)

    def items(self):
        return list(self._attrs.items())

    def values(self):
        return list(self._attrs.values())


class AttributesNSImpl(AttributesImpl):
    """Namespace-aware attributes: a name is an `(uri, localname)` pair.

    `attrs` maps that pair to the value; `qnames` maps the same pair to the
    prefixed spelling. The two tables are kept separate exactly as upstream
    does, because the qname lookups have to invert one against the other.
    """

    def __init__(self, attrs, qnames):
        self._attrs = attrs
        self._qnames = qnames

    def getValueByQName(self, name):
        for nsname in self._qnames:
            if self._qnames[nsname] == name:
                return self._attrs[nsname]
        raise KeyError(name)

    def getNameByQName(self, name):
        for nsname in self._qnames:
            if self._qnames[nsname] == name:
                return nsname
        raise KeyError(name)

    def getQNameByName(self, name):
        return self._qnames[name]

    def getQNames(self):
        return list(self._qnames.values())

    def copy(self):
        # Same workaround as AttributesImpl.copy above.
        return AttributesNSImpl(self._attrs, self._qnames)
