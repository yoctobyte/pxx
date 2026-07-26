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

## What we may write, and what we may not

Not legal advice; this is the working line the project holds, and it matches long
practice (Wine, Samba, the Nimbus fonts, clean-room BIOS work).

**Free to do:**
- Implement any library's API from its published documentation and observed
  behavior, in our own code. Copyright protects their EXPRESSION — their source —
  not the interface: not the module name, the function names, the parameter names,
  or the call shapes.
- Name our unit after the module it implements, so importing code resolves
  unchanged. `reportlab.pas` implementing reportlab's canvas API is interface
  naming, the same way `Nimbus Sans` implements Helvetica's metrics. (We used
  exactly that font substitution for the songformatter preview.)
- Vendor a third-party library whose licence permits it, keeping its notices
  intact — pdfgen is public domain, which is why it was chosen. See
  `decide-3rd-party-vendor-vs-fetch` for the general policy.

**Must not do:**
- Copy their source, or transcribe it while "rewriting". Clean room means written
  from the interface, not from their implementation. If you have read their code
  closely, say so in the ticket and prefer a different implementer.
- Copy their documentation text into our headers.
- Claim, in release notes, the website or a README, that pxx RUNS reportlab (or
  PIL, or any package) when what it runs is our shim. Trademark and plain honesty
  both land here, and it is the same discipline as the two byte-identicals note in
  CLAUDE.md: say "a reportlab-compatible canvas", never "reportlab".
- Imply endorsement by the upstream project.

**Rule of thumb:** the NAME is an interface, the CODE is theirs, the CLAIM is ours
to get right.

### EU law is explicit about this

Not legal advice, but the authorities are unusually clear and worth naming, since
this project is developed in the EU:

- **Software Directive 2009/24/EC, Art. 1(2)** — ideas and principles underlying
  any element of a computer program, **including its interfaces**, are not
  protected by copyright. The interface is fair game by statute, not just by
  practice.
- **CJEU C-406/10, SAS Institute v World Programming (2012)** — neither the
  FUNCTIONALITY of a program, nor its programming language, nor its data file
  formats are protected expression. World Programming reimplemented the SAS
  language from observed behaviour and prevailed. Reimplementing what a library
  DOES, from the outside, is squarely lawful.
- **Art. 5(3) and Art. 6** allow observing/studying a program to determine its
  ideas, and decompilation for interoperability, within limits.
- **Trademark, EUTMR Art. 14(1)(c)** — referential use to indicate the intended
  purpose of a product is expressly permitted. "reportlab-compatible" and "mimics
  reportlab" are exactly that form.

What none of this licenses is copying their source or documentation text: the
expression stays theirs. The line is the same one as above, now with a statute
behind it.

### Two different names, do not conflate them

- The **identifier** must be EXACT. `import reportlab` resolves to a unit called
  `reportlab` and nothing else — the naming strategy has no value otherwise. Same
  for `re`, `configparser`, `tkinter`.
- The **label** — in the ticket title, the docs, the website, release notes — is
  descriptive: "mimic-reportlab", "a reportlab-compatible canvas". That is the
  referential use trademark law permits, and it keeps the claim honest.

So: exact name in the code, descriptive name in the prose. Never the reverse.

## Concrete blocker for T1-by-naming

`from reportlab.pdfgen import canvas` is a DOTTED module path. NilPy maps `import X`
onto the Pascal unit resolver, and a unit name cannot contain a dot, so a unit
called `reportlab` alone does not satisfy that import. A package convention is
needed — a `lib/py/reportlab/pdfgen.pas` layout with dotted paths resolved onto it,
or a documented mangling. Until then, T1 shims only work for modules imported by a
single bare name (`re`, `configparser`, `tkinter`, `json`).

Tracked as `feature-nilpy-dotted-package-imports`.

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
