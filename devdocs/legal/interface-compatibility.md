# Interface compatibility: what pxx may implement, and what it must not claim

A standing project position, not advice from a lawyer. It exists because the
question recurs — every language pxx accepts eventually meets a library its
programs import, and someone has to decide whether we may write a compatible one
and what we may call it.

Technical policy (which tier, which backend, how a shim is tested) lives in
`devdocs/dev/python-compat-tiers.md`. This file is only the reasoning about
legitimacy.

## The position

**Implementing someone else's interface is fair game. Copying their code is not.
Claiming to BE them is not.**

Everything below is that sentence, expanded.

## Why the interface is fair game

A published interface is not the work — it is the coordination point between works.

- **Software Directive 2009/24/EC, Art. 1(2)** — ideas and principles underlying
  any element of a computer program, **including its interfaces**, are not
  protected by copyright. This is statute, not custom.
- **CJEU C-406/10, SAS Institute v World Programming (2012)** — neither a
  program's FUNCTIONALITY, nor its programming language, nor its data file formats
  are protected expression. World Programming reimplemented the SAS language from
  observed behaviour and prevailed.
- **Art. 5(3) and Art. 6** permit observing and studying a program to determine the
  ideas behind it, and decompilation for interoperability, within limits.
- The practice is old and uncontroversial: Wine, Samba, glibc, the Nimbus fonts
  against Helvetica's metrics, clean-room BIOS work. pxx itself used the Nimbus
  substitution for the songformatter preview.

**De-facto standard, de-facto legislation.** When an interface becomes the point
every program in an ecosystem depends on, it stops being one vendor's private
artefact and starts being the public coordination layer. `import reportlab` is a
dependency specifier before it is anything else: the ecosystem standardised on that
identifier, and a program that names it is naming a contract, not endorsing a
supplier. A compatible implementation has to answer to the same identifier or it
cannot be compatible at all. That is not appropriation; it is what compatibility
MEANS.

## The compiler is a tool, not a user of the mark

A separate and simpler point, which covers the compiler even before any of the
argument above is reached: **no law obliges a compiler to refuse source code
because an identifier in it is trademarked.**

When songformatter writes `import reportlab`, that line is the USER's document. The
compiler reads it, resolves it and emits code. That is mechanical processing of
text someone else wrote — the same act performed by a text editor displaying the
word, a linter parsing it, a package manager fetching by it, or `grep`. Trademark
law governs use of a sign **in the course of trade, as an indication of origin**.
Resolving an identifier inside a third party's source is none of those things: pxx
is not offering goods under that sign, and no one encountering the compilation
thinks the mark tells them who made pxx.

The obligation runs the other way, in fact. A compiler's job is to compile the
program as written. A tool that refused input over the trademark status of a
symbol in it would be broken as a tool, and the rule would be unworkable — any
identifier can be somebody's mark.

Where the boundary actually sits, and it is already covered above: what we SHIP
(our own code, plus anything vendored under its licence) and what we CLAIM (never
that pxx runs reportlab when it runs our shim). Compiling is free; branding and
asserting are the parts to get right.

## Why our code is clean

- Written from published documentation and observed behaviour, never from reading
  their source. If an implementer has studied the original's code closely, say so
  in the ticket and prefer a different implementer.
- No transcription-with-renaming. "Rewrote it in Pascal" is copying.
- No lifting of their documentation text into our headers or docs.
- Every shim is tested against the ORIGINAL's output, not against our expectations
  of it — the `re`, Counter, tuple and configparser suites all diff against CPython
  for the same script. That is evidence of compatibility, and it is also evidence
  of independent implementation: we are matching observable behaviour, which is
  precisely the lawful method.

## Naming: three names, kept apart

| what | whose | example |
| --- | --- | --- |
| the file / unit | ours | `mimic_reportlab.pas` |
| the import identifier | theirs, and must match | `import reportlab` |
| the label in prose | descriptive | "a reportlab-compatible canvas" |

Resolution is a MAPPING: `import reportlab` resolves onto `mimic_reportlab`. So no
file in the tree carries the upstream name — the name appears only where a program
writes it, identifying an interface rather than badging origin. That is the
textbook shape of referential use, which **EUTMR Art. 14(1)(c)** expressly permits:
using a sign to indicate the intended purpose of a product.

The tree is also self-documenting under this scheme, which matters for the honesty
of the thing: anyone opening `mimic_reportlab.pas` can see immediately that it is a
compatible implementation and not vendored upstream code.

## What we must never claim

This is where the real exposure is, and it is about honesty as much as law:

- Never say pxx "runs reportlab" (or PIL, or numpy) when what it runs is our shim.
  Say "a reportlab-compatible canvas", or name the shim.
- Never imply endorsement, affiliation or origin.
- Never let a benchmark, release note or website claim rest on a substitution the
  reader would not expect. Same discipline as the two byte-identicals note in
  CLAUDE.md: the qualifying words carry the whole distinction, and terse copy drops
  them first.
- A build should be able to SHOW this rather than assert it: the compiler reports
  `reportlab -> mimic_reportlab (shim, subset)`, and `--no-shims` makes any
  substitution an error. When a program compiles under `--no-shims`, "no lookalikes
  involved" is a fact you can demonstrate.

## Objections considered

Run against the position deliberately, so it is not re-argued from scratch each
time. Each is stated as an opponent would put it, with the answer.

**"Your implementation copies theirs."** Infringement requires SHOWING copying of
protected expression — substantial similarity, pointed at, in material that is
itself protectable. Not asserted, shown. Put the two side by side: ours is Pascal
over a public-domain C backend; theirs is a pure-Python library with its own PDF
writer and its own architecture. Similarity fails on inspection. Any fragment that
did resemble theirs would still have to clear triviality — short functional
constructs, the obvious way to write a loop, names dictated by the interface, are
not protectable (merger, scènes à faire, de minimis).

**"You reimplemented an interface you had no right to."** The interface is excluded
from protection by statute (Software Directive Art. 1(2)) and by CJEU C-406/10:
functionality, language and file formats are not protected expression. Nothing to
have a right to.

**"Compiling a program that names a trademark is trademark use."** No. That line is
in the USER's document; the compiler processes text, as an editor or a linter does.
Trademark reaches use in the course of trade as an indication of origin, which this
is not. See the section above.

**"Naming your shim after their module is trademark use."** No file in this tree
carries the upstream name; resolution is a mapping onto `mimic_*`. Where the name
does appear, it appears as the import identifier an ecosystem standardised on —
referential use, permitted by EUTMR Art. 14(1)(c).

**"You tested against their software."** Against open-source software under
permissive licences (CPython, PSF; reportlab, BSD), which carry no term restricting
study, reimplementation or benchmarking. Observing what published open-source code
does is unremarkable, and Art. 5(3) protects it besides. The rule this leaves is
narrow and prospective: before deriving expectations by RUNNING a proprietary
package, read its licence.

**"Your `--no-shims` flag admits the substitution matters."** It does matter, and
saying so plainly is the point. Disclosure is what honest practices look like; a
project that reports its substitutions and can prove their absence on demand is
demonstrating good faith, not confessing to something.

**"Your shim might be incorrect."** It might. Nothing here warrants correctness —
no fitness, no merchantability, no guarantee — exactly as every compiler and every
library in this ecosystem ships. Bugs are not torts. What WOULD matter is a false
CLAIM that induced reliance ("drop-in replacement"), which is why the claims rules
above are the strict part of this document.

## The correctness rule is ours, not the law's

Shims fail loudly outside their subset and their expectations are diffed against
the original's own output. That is engineering discipline, held because silently
wrong output is the failure class this project treats as worst — not because any
law requires it and not as an admission that any is owed. Do not read it as a
warranty; there is none.

## Jurisdiction

The reasoning above is EU law, where this project is developed. Elsewhere the route
differs — in the US the argument for reimplementing an interface runs through fair
use for interoperability rather than through exclusion from protection, the ground
Oracle litigated for a decade against Google and lost. Different mechanism, same
practical destination; the conduct rules in this document are written to satisfy
both.

## Vendoring is a different question

Taking someone's code into the tree — pdfgen, zlib, sqlite — is governed by their
licence, not by this document. pdfgen is public domain, which is why it was chosen
as the PDF backend. The general policy is `decide-3rd-party-vendor-vs-fetch`.
Whatever is vendored keeps its notices intact.

## In one line

The name is an interface, the code is ours, the claim is the thing to get right.
