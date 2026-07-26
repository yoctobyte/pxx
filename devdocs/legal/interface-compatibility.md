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

## Vendoring is a different question

Taking someone's code into the tree — pdfgen, zlib, sqlite — is governed by their
licence, not by this document. pdfgen is public domain, which is why it was chosen
as the PDF backend. The general policy is `decide-3rd-party-vendor-vs-fetch`.
Whatever is vendored keeps its notices intact.

## In one line

The name is an interface, the code is ours, the claim is the thing to get right.
