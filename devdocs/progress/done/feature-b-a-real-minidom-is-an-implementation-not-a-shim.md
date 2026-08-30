---
track: B
prio: 20
type: feature
blocked-by: [bug-n-a-class-with-two-definitions-of-one-method-hangs-the-compiler-forever]
summary: "Question 2 of the xml.dom row, re-filed on its own as that ticket said it should be. html5lib/treebuilders/dom.py wants a document you can build and mutate — ~25 DOM methods, getDOMImplementation().createDocument(), weakref.proxy(), and a reach into minidom's PRIVATE _child_node_types. That is a DOM implementation, not a compatibility alias. It unblocks exactly one corpus file and should be ranked as an implementation project, not alongside shims."
status: done
owner: frankB
---

# A real `minidom` is an implementation, not a shim

- **Type:** feature (library) — **Track B**.
- **Filed:** 2026-08-18 by frank3-fc, splitting
  [[feature-nilpy-xml-dom-is-two-questions-not-one]] as that ticket instructed:
  *"Question 2 should be re-filed as its own ranked item if a real DOM is ever
  wanted. Do not let it ride along with question 1 under one row."*
  Question 1 (`Node`'s twelve constants) is done and shipped as
  `lib/rtl/mimic_xml_dom.py`. This is the other half, standing alone.

## The one caller, and what it actually wants

`html5lib/treebuilders/dom.py` (239 lines) builds and mutates a document:

```
appendChild attributes childNodes cloneNode createComment createDocumentFragment
createElement createElementNS createTextNode firstChild hasAttributes
hasChildNodes insertBefore namespaceURI nodeName nodeType nodeValue normalize
ownerDocument publicId removeChild setAttribute setAttributeNS systemId
getDOMImplementation createDocument createDocumentType
```

plus two things that are not DOM API at all:

- `weakref.proxy(self)` (line 126) — needs a `weakref` module, which does not
  exist here and is a runtime facility rather than a shim.
- a reach into a **private CPython implementation detail** (line 170):

```python
if hasattr(self.dom, '_child_node_types'):
    if Node.TEXT_NODE not in self.dom._child_node_types:
        self.dom._child_node_types = list(self.dom._child_node_types)
        self.dom._child_node_types.append(Node.TEXT_NODE)
```

html5lib is patching minidom's private class-level list of permitted child
types so the document can hold text nodes. The `hasattr` guard says the caller
knows it is reaching into someone's internals. A shim would have to reproduce
not just the DOM but *that specific internal*, under its exact name, for the
guard to fire.

## Why it stays at p15

- It unblocks **one** corpus file, and that file is an optional tree backend —
  html5lib's default treebuilder is `etree`, and `dom.py` is what you get only
  by asking for it.
- It is genuinely large: a conforming-enough DOM plus `weakref`.
- Nothing else in the corpora wants a DOM.

Rank it up if an application wants to build XML documents — that is a real
capability and would be the reason to do it, not this one file.

## What would make it tractable

Not "write minidom". The honest decomposition, if it is ever wanted:

1. `weakref` first, or decide `weakref.proxy` can be identity here and say so
   loudly — it is a lifetime facility, and getting it silently wrong is the
   usual shape of trouble.
2. A DOM core (`Document`, `Element`, `Text`, `Comment`, `DocumentFragment`,
   `DocumentType`) with the node-tree operations, tested by value against
   CPython's minidom the way the other `mimic_*` differentials are.
3. Only then the `_child_node_types` internal, and with a comment saying which
   caller depends on it and why.

## 2026-08-30 (frankB) — piece 1 landed, and the stated payoff is NOT reachable from Track B

Claimed and worked in pieces, with the CPython differential as each piece's gate.
**The first thing measured was the ticket's own premise, and it does not hold as
written.**

### The wall order, measured against pin v393 — not inherited from this ticket

The ticket presents minidom as what stands between the tree and
`html5lib/treebuilders/dom.py`. Compiling that file says otherwise. In the order
the compiler hits them:

| # | wall | lane | state |
| --- | --- | --- | --- |
| 1 | `import weakref` — *no unit named weakref and no shim mimic_weakref* | **B** | **CLEARED** below |
| 2 | `property(...)` as a builtin NAME — `base.py:321` | **N** | [[bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name]] |
| 3 | `from xml.dom import minidom` binds nothing | **B** | this ticket |

**Wall 2 sits between the two Track B walls.** `@property` as a *decorator*
compiles and works; `property` as a *name* does not exist, so
`v = property(_g, _s)` is `undefined variable (property)`. That is a frontend
gap, filed in N rather than worked around here, per the rule about a library not
routing around a compiler gap.

So this ticket's stated payoff — *"It unblocks exactly one corpus file"* — **cannot
be delivered from Track B at all** while wall 2 stands. Whoever finishes the DOM
should expect the corpus file to stay red, and should not read that as the DOM
being wrong.

**Which changes the gate, and the ticket already anticipated it.** Its own
decomposition says the DOM should be *"tested by value against CPython's minidom
the way the other `mimic_*` differentials are"*. That differential is the real
gate; the corpus file is the motivation. Saying so now rather than discovering it
at the end.

### Piece 1: `lib/rtl/mimic_weakref.py` — `proxy` only, and the refusals are the content

`weakref.proxy(obj)` returns `obj`. The runtime is refcounted with no cycle
collector and no weak-reference support (grepped: nothing in `lib/rtl` or the
compiler implements one), so the reference is strong. Output is identical; the
divergence is a **leak** — `base.TreeBuilder:194` does
`self.document = self.documentClass()` and `dom.py:126` returns
`weakref.proxy(self)`, so `self.document` is `self`, a cycle, one leaked
TreeBuilder per parse. Stated loudly in the file's header because it is the kind
of cost that disappears once a green appears.

**`ref`, `WeakKeyDictionary`, `WeakValueDictionary`, `WeakSet`, `finalize` are
deliberately ABSENT, and two of them are wanted by the corpus** (`weakref.ref`
twice, `WeakKeyDictionary` once, in reportlab). They are refused because a
strong version is silently wrong in the branch-taking way: `ref(x)` exists to
answer `None` once the target dies, so a strong one makes `if r() is None:` take
the wrong branch forever — the same shape as `mimic_xml_dom`'s `0 == 0`
near-miss. `python-compat-tiers.md` asks for exactly this: *"states its subset in
its own header and fails LOUDLY outside it. It never approximates."*

**The loudness was verified, not assumed** — `weakref.ref(t)` gives
`pascal26:5: error: no member ref came of the qualifier weakref`, at the use
site, naming the member.

### Piece 1's gate

`test/lib_mimic_weakref.npy` is a differential: it runs unmodified under CPython,
and both outputs are **byte-identical** (13 lines, 11 checks). It asserts only
what the two interpreters AGREE on — forwarding of reads, writes and calls. The
three divergences (`proxy(x) is x`, `type(proxy(x))`, lifetime) are deliberately
NOT asserted: a differential pins agreement, and asserting a difference would
make the file fail under one interpreter. It is written to still pass unchanged
if `proxy` ever becomes a real weak reference.

### Correction to this ticket's demand list

The surface list above omits `createAttribute`, which `dom.py` calls. Measured
off the file rather than copied forward. Minor, but the list is what the next
piece is sized against.


## 2026-08-30 — PARKED. The implementation is written; the compiler cannot build it.

**State: done except for landing.** The DOM is complete (452 lines: `Document`,
`Element`, `Attr`, `Text`, `Comment`, `DocumentFragment`, `DocumentType`,
`NamedNodeMap`, `DOMImplementation`, the exception types, namespace-aware
create/set, deep and shallow `cloneNode`, `normalize`). Its CPython differential
is written, banked and **passing against the real `xml.dom.minidom`** —
`test/lib_mimic_xml_dom_minidom.npy`, 34 checks over tree structure, attribute
storage, text/comment nodes, namespace splitting and cloning.

**Why it is not in `lib/rtl`:** putting it there hangs the compiler forever —
100% CPU, flat RSS, no output, no exit. Filed as
[[bug-n-a-class-with-two-definitions-of-one-method-hangs-the-compiler-forever]]
with a 9-line repro. Any lane running `make lib-test` with this file present
would hang and read it as a slow box, so the file stays out until that closes.

The source is parked in-tree at `lib/rtl/mimic_xml_dom_minidom.py.parked` — the
suffix is deliberate, since only `*.pas` and `*.py` are picked up by the build.
It is **not** reshaped to dodge the hang: renaming the one local variable that
triggers it would build today and hide the bug, which the platonic-code rule
forbids. `blocked-by` now names the hang so the ranker will not dispatch this.

**To finish, once the hang is fixed:** rename `.parked` to `.py`, add the two
Makefile lines below after the `lib_mimic_weakref.2` entry, and run the
differential — no code changes are expected, because the test already passes
against CPython and the module is written to that same contract.

```make
	$(PXX_STABLE) -Fulib/rtl test/lib_mimic_xml_dom_minidom.npy $(TESTTMP)/lib_mimic_xml_dom_minidom
	tools/expect_same.sh lib_mimic_xml_dom_minidom.1 "$($(TESTTMP)/lib_mimic_xml_dom_minidom | grep -c '=ok')" "34"
	tools/expect_same.sh lib_mimic_xml_dom_minidom.2 "$($(TESTTMP)/lib_mimic_xml_dom_minidom | tail -1)" "MIMIC-MINIDOM OK"
```

One finding fell out of the import work and is filed separately:
[[bug-n-from-package-import-submodule-binds-the-parent-package]] — `from xml.dom
import minidom` binds the parent package, so the differential uses `from
xml.dom.minidom import ...`, which resolves correctly under both interpreters.

Moved from `working/` to `unfinished/`: `working/` is a live lock, and this
cannot proceed from any lane until the compiler stops hanging.

## 2026-08-30 — the hang is FIXED, and this stays parked anyway

frankA's `0425a62c8` ("unlink a symbol from the bucket it was FILED in, not from
its name now") fixes the compiler hang this ticket is blocked by, and reports the
parked file building in 4.01s with its differential matching CPython on all 36
checks. That is a Track A measurement against a compiler built at HEAD, and I
have no reason to doubt it.

**It does not unblock Track B, because Track B does not build with HEAD.** The
lane builds everything with `$(PXX_STABLE)` = `stable_linux_amd64/default/pinned`,
and the current pin is **v394 `53800fbeb0b66e11`**, built from `43c8e3412`
(2026-08-30 06:11). The fix landed at 09:03. `git merge-base --is-ancestor
0425a62c8 43c8e3412` is false: **the pinned compiler predates the fix.**

Measured rather than inferred, since a sha argument about a binary deserves a
run: the pinned compiler on the parked source spins for the full 75s timeout at
100% CPU, exactly as before. Unparking now would put a file into `lib/rtl` that
`make lib-test` cannot compile, and the failure mode is a hang rather than an
error — the worst shape for a gate, because it does not fail, it stops.

**Unpark condition, precisely:** a pin whose source commit has `0425a62c8` as an
ancestor. Check it with

```
git merge-base --is-ancestor 0425a62c8 $(awk 'END{print $NF}' stable_linux_amd64/default/pin.log)
```

and confirm with a real compile of the parked file by `$(PXX_STABLE)` before
renaming. The `blocked-by` edge stays, because the condition it names — *this
lane can build the file* — is still false; only the reason changed, from "the
compiler has a bug" to "the compiler Track B is required to use does not yet have
the fix".

Everything else in the finish list below is unchanged and still correct.

## 2026-08-30 (frankB) — UNPARKED and LANDED at pin v395

The unpark condition the previous entry wrote down was met, and it was checked
the way that entry demanded — by a real compile, not by reading a sha.

**The condition, evaluated:** `git merge-base --is-ancestor 0425a62c8
acec6c192f14` (the v395 pin's source commit) is **true**. v394's source
`43c8e34120` was not an ancestor, which is why the previous session stopped.

**The compile, measured** — because "the fix is in the pin" is an argument about
a binary and deserves a run:

| pin | result on this file |
| --- | --- |
| v394 `53800fbeb0b6` | spun the full 75s timeout at 100% CPU |
| **v395 `aa78a7faf63a`** | **ok in 2.9s** (`code=1318680B procs=1918`) |

Compiled first from a scratch dir while `make lib-test` was still running, then
again from its real `lib/rtl` home once that finished — deliberately not
dropping a possible hang into a live gate run.

**The differential is green from the real location:** output **byte-identical**
to CPython's real `xml.dom.minidom`, 34/34 `=ok`, `MIMIC-MINIDOM OK`. Both
Makefile assertions run and exit 0.

**Landed:**
- `lib/rtl/mimic_xml_dom_minidom.py.parked` → `.py` (`git mv`), and the
  `PARKED -- NOT BUILDABLE` banner replaced with the history: why it was parked,
  why it was not reshaped to dodge the hang, and the *two-step* unpark condition
  (fix lands ≠ fix is usable here, because this lane builds with `$(PXX_STABLE)`).
- The three Makefile lines wired after `lib_mimic_weakref.2`, with a comment
  guarding the load-bearing import spelling so nobody "modernises"
  `from xml.dom.minidom import ...` back to the form that silently binds the
  parent package.

**Neighbours checked, not assumed:** `lib_mimic_xml_dom` (20 checks) and
`lib_mimic_weakref` still pass with this module now present — it is reached
through `mimic_xml_dom.py`'s `minidom` binding, so its arrival could have
changed that module's behaviour. It did not. `tools/lib_units_compile.py` scans
only `*.pas`, so the 142-unit count is unchanged.

### What this does NOT deliver, restated so nobody re-reads the ticket as a win

The ticket's stated payoff — *"unblocks exactly one corpus file"* — is **still
not delivered, and not by Track B**. `html5lib/treebuilders/dom.py` needs
`property(...)` as a builtin NAME, which this dialect does not have
([[bug-n-property-works-as-a-decorator-but-is-not-a-builtin-name]], Track N).
The DOM is complete and gated; the corpus file stays red for a reason that has
nothing to do with it. That was the previous session's finding and landing the
code does not change it.

**Resolving** on the gate the ticket itself named — the CPython differential —
not on the corpus file it was motivated by.

## Log
- 2026-08-30 — resolved, commit d84323289.
