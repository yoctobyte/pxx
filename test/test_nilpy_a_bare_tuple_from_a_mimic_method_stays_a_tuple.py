# Regression test for bug-n-a-bare-tuple-returned-from-a-mimic-module-method-arrives-as-its-string-repr
# (closed 2026-11-10: it passes at latest; expected = python3).
from xml.sax.xmlreader import AttributesNSImpl
XLINK = "http://www.w3.org/1999/xlink"
attrs  = {(None, "class"): "hero",  (XLINK, "href"): "http://example.org/"}
qnames = {(None, "class"): "class", (XLINK, "href"): "xlink:href"}
a = AttributesNSImpl(attrs, qnames)
r = a.getNameByQName("xlink:href")
print("type:", type(r).__name__)
print("repr:", repr(r))
print("eq:",   r == (XLINK, "href"))
