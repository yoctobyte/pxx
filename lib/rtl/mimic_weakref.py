# SPDX-License-Identifier: 0BSD
"""mimic_weakref -- `weakref.proxy`, and deliberately nothing else.

Reached as `import weakref`, which the NilPy import resolver maps to this file
and announces (`note: weakref -> mimic_weakref (shim, subset)`). Not named
`weakref.py`: no file in this tree carries an upstream module name.

THERE ARE NO WEAK REFERENCES HERE, AND THAT IS THE WHOLE HEADER.
The runtime is reference-counted with no cycle collector and no weak-reference
support -- grep for it: nothing in `lib/rtl` or the compiler implements one. So
this file cannot make a reference weak. What it can do is provide the ONE name
whose divergence is a leak rather than a wrong answer, and refuse the ones whose
divergence would be a wrong answer.

WHY `proxy` IS PROVIDED, AND EXACTLY WHAT IT COSTS.
`proxy(obj)` returns `obj`. Every attribute access, call and comparison through
it behaves identically to CPython's proxy while the target is alive, so a caller
that never outlives its target cannot observe the difference in its OUTPUT. What
it does observe is lifetime: the reference is strong, so a structure that was
acyclic under CPython becomes a cycle here and is never freed.

The one corpus caller is `html5lib/treebuilders/dom.py:126`:

    def documentClass(self):
        self.dom = Dom.getDOMImplementation().createDocument(None, None, None)
        return weakref.proxy(self)

and `base.TreeBuilder:194` stores it as `self.document = self.documentClass()`.
So under CPython `self.document` is a weak proxy back to `self`; here it is
`self` itself. **That leaks one TreeBuilder per parse**, and the parse output is
byte-identical. Stated in the loudest terms available because it is precisely the
kind of cost that gets forgotten once a green appears: correct output, growing
process.

Two smaller divergences, for completeness rather than because a caller hits them:
`proxy(x) is x` is True here and False under CPython, and `type(proxy(x))` is the
target's type rather than `weakproxy`. No corpus site inspects either.

DELIBERATELY ABSENT: `ref`, `WeakKeyDictionary`, `WeakValueDictionary`,
`WeakSet`, `finalize`, `ReferenceType`.

This is not laziness and it is not "not needed yet" -- two of them ARE wanted by
the corpus (`weakref.ref` twice, `weakref.WeakKeyDictionary` once, all in
reportlab). They are refused because a strong-reference version of them is
SILENTLY WRONG in the branch-taking way, which is the failure class this project
ranks worst:

  * `ref(x)` returns a callable whose whole purpose is to answer `None` once the
    target dies. A strong version always answers the object, so
    `if r() is None:` takes the wrong branch forever -- and nobody writes
    `weakref.ref` unless they are going to ask that question. Compare
    mimic_xml_dom's header: a complete-looking shim answering `0 == 0` passed
    every test that checked resolution instead of values.
  * `WeakKeyDictionary` as a strong dict never drops an entry, so a cache keyed
    on live objects grows without bound. Wrong output arrives late and far from
    here.

An absent name is a compile error at the use site, which is the outcome
devdocs/dev/python-compat-tiers.md asks for: "A shim states its subset in its own
header and fails LOUDLY outside it. It never approximates."

T3 DEFERRAL, per the same document's rule that every T1 shim names the ticket it
defers to: feature-nilpy-runtime-weak-references. Until that exists, `ref` and
the weak containers are not implementable honestly at any tier, because the gap
is in the object model rather than in this file.
"""


def proxy(obj, callback=None):
    """CPython's `weakref.proxy`, minus the weakness. Returns `obj` itself.

    `callback` is accepted and IGNORED -- it fires on target death, and nothing
    here can ever observe a target dying. It is in the signature so a caller that
    passes one gets the documented leak rather than a TypeError that would send
    the reader hunting in the wrong place.
    """
    return obj
