# SPDX-License-Identifier: 0BSD
"""mimic_xml_sax_saxutils -- CPython's `xml.sax.saxutils` escaping helpers.

Reached as `from xml.sax.saxutils import escape, unescape`, which the NilPy
import resolver maps to this file (dotted module name -> `mimic_xml_sax_saxutils`)
and announces as a shim. Not named for the upstream package: no file in this
tree carries one, so the tree always says what a thing is.

WHAT THIS MODULE IS, AND WHY ONLY PART OF IT IS HERE. `xml.sax.saxutils` is two
unrelated things bolted together: three pure string functions (`escape`,
`unescape`, `quoteattr`), and a set of SAX filter/handler classes
(`XMLGenerator`, `XMLFilterBase`, `prepare_input_source`) that are part of the
SAX machinery and need a parser behind them. Only the string half is here. That
is not an approximation of the other half -- it is absent, so a caller reaching
for `XMLGenerator` gets a loud unresolved-name error rather than a class that
accepts a document and drops it.

THE ESCAPE SET IS EXACTLY CPYTHON'S, AND IT IS SMALLER THAN PEOPLE EXPECT.
`escape` replaces `&`, `<` and `>` -- and NOT the quote characters. Quotes are
`quoteattr`'s job, because they only need escaping inside an attribute value.
A shim that "helpfully" escaped quotes in `escape` would produce `&quot;` in
text nodes: still well-formed XML, different document. The order matters too:
`&` must be replaced first or the ampersands introduced by the later
replacements get escaped again, turning `<` into `&amp;lt;`. Both properties
are asserted in test/lib_mimic_xml_sax_saxutils.npy against CPython.

SCOPE. `html5lib/filters/sanitizer.py` imports `escape` and `unescape`.
`quoteattr` is included because it is the third of the same trio and the one a
caller reaches for when writing an attribute -- omitting it would invite an
open-coded version that gets the quote-selection rule wrong.
"""


def escape(data, entities=None):
    """Escape `&`, `<` and `>` in a string of character data.

    `entities`, when given, is a mapping of extra characters to replace, applied
    after the three mandatory ones -- the same contract as CPython's.
    """
    data = data.replace("&", "&amp;")
    data = data.replace("<", "&lt;")
    data = data.replace(">", "&gt;")
    if entities:
        for k in entities:
            data = data.replace(k, entities[k])
    return data


def unescape(data, entities=None):
    """The inverse of `escape`.

    `&amp;` is undone LAST, mirroring `escape` doing it first: otherwise the
    text `&amp;lt;` -- an escaped literal `&lt;` -- would come back as `<`
    instead of `&lt;`.
    """
    data = data.replace("&lt;", "<")
    data = data.replace("&gt;", ">")
    if entities:
        for k in entities:
            data = data.replace(k, entities[k])
    return data.replace("&amp;", "&")


def quoteattr(data, entities=None):
    """Escape and quote an attribute value, choosing the quote character.

    CPython's rule, reproduced exactly: prefer `"`; if the value contains one,
    use `'`; if it contains both, use `"` and escape the embedded `"` as
    `&quot;`. Newlines, tabs and carriage returns are escaped numerically,
    because an unescaped one inside an attribute is normalised away by an XML
    parser and would silently change the value.
    """
    entities_all = {"\n": "&#10;", "\r": "&#13;", "\t": "&#9;"}
    if entities:
        for k in entities:
            entities_all[k] = entities[k]
    data = escape(data, entities_all)
    if '"' in data:
        if "'" in data:
            data = '"' + data.replace('"', "&quot;") + '"'
        else:
            data = "'" + data + "'"
    else:
        data = '"' + data + '"'
    return data
