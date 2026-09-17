---
track: N
prio: 60
type: bug
blocked-by: []
summary: "A BARE tuple returned from a method of a class in a mimic (lib/rtl) module arrives at the caller as a STRING holding the tuple's repr: type(r) is str and r == (a, b) is False. A tuple inside a returned LIST survives intact, and the identical code in a plain local module or inline is correct -- so this is the mimic-module return route, not tuples, not dict iteration, and not imports generally. Found as the single failing assertion (24 of 25) in test/lib_mimic_xml_sax_xmlreader.npy, which Track T auto-filed against an unrelated compiler-only sha."
status: unfinished
owner: unassigned
---

# A bare tuple returned from a mimic-module method becomes its repr

## Repro — nine lines, against the real shim

```python
from xml.sax.xmlreader import AttributesNSImpl
XLINK = "http://www.w3.org/1999/xlink"
attrs  = {(None, "class"): "hero",  (XLINK, "href"): "http://example.org/"}
qnames = {(None, "class"): "class", (XLINK, "href"): "xlink:href"}
a = AttributesNSImpl(attrs, qnames)
r = a.getNameByQName("xlink:href")
print("type:", type(r).__name__)
print("repr:", repr(r))
print("eq:",   r == (XLINK, "href"))
```

| | CPython | pxx |
| --- | --- | --- |
| `type` | `tuple` | **`str`** |
| `repr` | `('http://…/xlink', 'href')` | **`"('http://…/xlink', 'href')"`** |
| `eq` | `True` | **`False`** |

The shim is not at fault: `mimic_xml_sax_xmlreader.py:122` iterates `self._qnames`
and returns the KEY, which is the right answer and the right object.

## THE ROUTE IS THE VARIABLE — three controls, and two of them do NOT reproduce

Written out because each one removes a suspect, and the first two are where the
obvious hypotheses die:

- **Dict iteration over tuple keys — CORRECT.** Inline, with the test's exact
  shapes including the `(None, "class")` key: `type: tuple`, right repr,
  `eq: True`. This was my first hypothesis and it is wrong.
- **A plain local imported module — CORRECT.** A hand-written `mymod.py` with a
  class whose method returns a dict key, imported normally, returns a real
  tuple. So it is not "crossing a module boundary" and not "a method return".
- **The mimic route — WRONG.** Same construct, same types, through
  `from xml.sax.xmlreader import …`.

**And a tuple inside a returned LIST survives.** In the same run,
`(XLINK,"href") in a.getNames()` is `ok` — `getNames()` returns a list of
tuples and the tuples are intact. Only the BARE tuple return degrades, which is
the sharpest clue available: something on the mimic return path marshals a
top-level tuple to text while leaving a container's elements alone.

That asymmetry is also the positive control this ticket needs — 24 of 25
assertions pass, including every string, int, bool, and list-of-tuples row, so a
fix that merely makes the file green without restoring `type(r) is tuple` has not
fixed it.

## Provenance — read this before re-attributing it

Auto-filed by Track T as `regression-lib-test-lib-mimic-xml-sax-xmlreader` at
`2b2ec3fee1c5`. **That sha cannot be the cause and the auto-ticket says so
itself**: the job builds with `$(PXX_STABLE)` and that commit touched only
`compiler/**` and `devdocs/**` — zero files the job reads. Verified with
`git show --name-only`. The named sha is the one that was TESTED, not bisected.

Nor is it a v411 regression in the "was working" sense: v410's binary cannot
compile the test at all against today's `lib/` tree (`AttributesNSImpl fails`),
so the pin is what made this row reachable. **It is a pre-existing gap the pin
EXPOSED, not one it introduced**, and the honest framing is that 24 of 25 newly
pass where previously none did.
