# Python library compatibility: tiers, naming, and what we may write

How pxx answers "this program imports a library we don't have". Written after the
songformatter port kept hitting it (`reportlab`, `configparser`, `tkinter`, `re`,
`json`), and after the first answer turned out to be the wrong one.

## The reversal that prompted this

The first design refused to name a pxx unit after the library it implements — it
felt like impersonation — so songformatter grew a fallback import instead:

```python
try:
    from reportlab.pdfgen import canvas     # cpython
except ImportError:
    from pxxpdf import canvas               # pxx
```

That put a change in the APPLICATION to work around a naming scruple in the
COMPILER's library set, which is backwards. The mission is to compile existing
source as-is ([[ir-as-substrate]] and the mission memory); every line an app has to
add is a line the mission failed to avoid. Name the unit `reportlab` and the app
needs no change at all.

So: **name shims after the module they implement.** The fallback import above stays
only until `reportlab` exists as a unit, then it comes out and songformatter is
untouched source again.

## The three tiers

**T1 — name-shim.** A pxx unit named for the Python module, presenting that
module's API over whatever backend fits: `re` over lib/rtl/regex.pas, `configparser`
over an INI reader, `tkinter` over tk.pas, `reportlab` over pdfgen. Cost: hours to
days. Application changes: none. This is what unblocks work today.

**T2 — vendored C core with a Python face.** When the real package is a thin skin
over C, compile the C with cfront and put the Python API on top: PIL over
libjpeg/zlib, `mupdf`, `sqlite3`. Cost: days. Legitimate and durable — this is what
absorbing a C library looks like.

**T3 — compile the actual package.** A real `.py` module loader in the Nil-Python
frontend: find a package's own sources, parse and lower them. Then a pure-Python
package works because we compiled IT, not a lookalike. Cost: a frontend subsystem.
This is the horizon, and the only tier that makes "toss any Python at pxx" true.

## The rule, not just the tiers

- **T1 to unblock, T3 as the target, T2 only when the package is genuinely C.**
- **Every T1 shim is filed with the T3 ticket it defers to**, so a shim is visibly
  temporary rather than quietly permanent.
- **A shim states its subset in its own header and fails LOUDLY outside it.** It
  never approximates. Getting an unsupported call wrong produces wrong output,
  which is the failure class this project treats as worst; an error at the use site
  is always better. lib/rtl/re.pas and configparser.pas both do this — read their
  headers for the shape.
- **A shim is measured against the real thing.** Every expectation in the re,
  Counter, tuple and configparser tests is CPython's own output for the same
  script, diffed. That is what keeps "compatible" from meaning "plausible".

## Legitimacy: see the legal note

Whether we may implement a named library at all, what "clean room" requires, and
what we may never claim, are a standing project position and live in
**`devdocs/legal/interface-compatibility.md`**. In one line: implementing someone
else's interface is fair game, copying their code is not, and claiming to BE them
is not. The naming scheme below follows from it.

### The import name is a MAPPING, not a filename (Rene, 2026-07-26)

The unit does not have to BE called `reportlab`. `import reportlab` RESOLVES to a
unit named `mimic_reportlab`, through the import resolver. That is better on every
axis:

- **No file in our tree carries their name.** The trademark surface in the artifact
  is zero. The name appears only as the import identifier the ecosystem
  standardised on — used to identify an INTERFACE, not to badge origin, which is
  the textbook shape of referential use.
- **The tree is self-documenting.** A reader who opens `mimic_reportlab.pas` knows
  at once it is a compatible implementation and not vendored upstream code. That is
  what the `pxxpdf` name was reaching for, now without costing the application a
  line.
- **It answers the dotted-path problem for free.** A mapping can mangle:
  `reportlab.pdfgen` -> `mimic_reportlab_pdfgen`. No package-directory machinery
  needed, and `os.path`, `xml.etree.ElementTree` and friends work the same way.
- **The substitution is traceable.** The compiler can report
  `reportlab -> mimic_reportlab (shim, subset)` so a build says out loud which
  imports were satisfied by a lookalike, and a `--no-shims` flag can make any
  substitution an error — which is how a T3 claim gets PROVEN later: "this compiled
  with no shims at all".

The defence, in one line: we never present our code as theirs, we provide a
compatible library, and the import name is a de-facto dependency specifier the
ecosystem chose. A library that also trademarked its import identifier does not
thereby prevent compatible implementations from being importable — that identifier
is the coordination point every program already names.

### Two different names, do not conflate them

- The **file and unit name** is ours and says what it is: `mimic_reportlab`.
- The **import identifier** is theirs and must match exactly, because that is what
  programs write: `import reportlab`. It is resolved onto our unit by the mapping
  above.
- The **label** in tickets, docs, website and release notes is descriptive:
  "mimic-reportlab", "a reportlab-compatible canvas" — never "reportlab".

Bare-name shims already in the tree (`re`, `configparser`, `tkinter`) are named
directly, which was the quick path. They should move behind the same mapping so
the rule is one rule.

> **Status checked 2026-08-30 (frankD), at `ea5d7c6e7`.** *"When it lands"* has
> happened — [[feature-nilpy-dotted-package-imports]] is in `done/` and the
> resolver tries `<name>` first, then falls back to `mimic_<name>`
> (`pyparser.inc`, `grep -n 'mimic_reportlab_lib'`). The three units have **not**
> moved: `lib/rtl/re.pas`, `lib/rtl/configparser.pas` and `lib/pcl/tkinter.pas`
> are still bare, next to `lib/pcl/mimic_tkinter_font.pas` — the convention is
> applied inconsistently inside one package family.
>
> **The alarming reading was tested and is false, which is the part worth
> recording.** A bare-named shim looks like it could shadow a user's own module,
> since the resolver's *first* probe is the bare name. It does not: with a local
> `re.py` defining `compile()` beside a program that does `import re`, the
> compiled binary prints `USER-RE`. The user's module wins. Compiled with
> `$(PXX_STABLE)`, two minutes, and it is the reason this is not a bug ticket.
>
> What is left is the naming rule's *other* purpose, from the section above —
> **a reader who opens `mimic_reportlab.pas` knows it is a subset shim, and a
> reader who opens `re.pas` has no such signal.** That is an expectation cost,
> not a correctness one, and no compiling program behaves differently either
> way. Deliberately **not** filed: a ticket that cannot name a program whose
> behaviour changes is one that sits in the ranker's scan forever at zero value.
> Recorded here instead so the next person to read this paragraph does not
> re-run the shadowing test.

## The blocker for T1-by-naming — RESOLVED 2026-07/08, kept for the reasoning

**This section described a live blocker until 2026-08-30 and no longer does.**
Read it as the argument that produced the design, not as a limit.

The problem was real: `from reportlab.pdfgen import canvas` is a DOTTED module
path, NilPy maps `import X` onto the Pascal unit resolver, and a unit name cannot
contain a dot — so a unit called `reportlab` alone does not satisfy that import.
Two ways out were offered above: a `lib/py/reportlab/pdfgen.pas` package layout
with dotted paths resolved onto it, **or a documented mangling.**

**The mangling shipped**, exactly as this page proposed it —
`reportlab.pdfgen` → `mimic_reportlab_pdfgen`. `feature-nilpy-dotted-package-imports`
is in `done/`, named for this page's own example, and the corpus uses the feature
routinely: `import xml.etree.ElementTree as ET`, `from urllib.request import
Request, urlopen`, `from six.moves import urllib_parse` all resolve today onto
`mimic_xml_etree_elementtree`, `mimic_urllib_request`, `mimic_six_moves`. The
package-directory layout was **not** built, which is why `lib/py/` does not exist
— that path above is the road not taken, not a stale citation.

> **Corrected 2026-08-30 (frankD), measured at `ea5d7c6e7`.** The sentence that
> mattered was *"Until then, T1 shims only work for modules imported by a single
> bare name (`re`, `configparser`, `tkinter`, `json`)."* **That limit has been
> false for weeks**, and it is the second one this audit found with the same
> signature: it does not merely assert the limit, it **explains** it — *a unit
> name cannot contain a dot* — and a reader who accepts the mechanism stops
> testing the conclusion. A false limit with a mechanism attached is the most
> durable wrong thing a doc can carry, because the mechanism is still true and
> only the consequence has moved.
>
> Verify rather than trust either version:
> `ls devdocs/progress/*/feature-nilpy-dotted-package-imports.md` says where the
> work sits, and `grep -l '^import [a-z_]*\.' test/*.npy` says whether the corpus
> actually uses it.

## Where the current shims stand

| module | tier | unit | notes |
| --- | --- | --- | --- |
| `re` | T1 | lib/rtl/re.pas | over lib/rtl/regex.pas; CPython-diffed |
| `configparser` | T1 | lib/rtl/configparser.pas | dependency-free INI; virtual optionxform |
| `tkinter` | T1 | lib/pcl/tkinter.pas | over tk.pas; first slice, widget subset |
| `collections.Counter` | T1 | pylib (dict mode) | from-import consumed by the frontend |
| `reportlab` | T1 planned | — | currently `pxxpdf`; rename once dotted imports land |
| PIL | T2 candidate | — | C extension; pdfgen embeds images natively for now |
| numpy | T3 only | — | C + BLAS + a build system; no shim is honest here |
